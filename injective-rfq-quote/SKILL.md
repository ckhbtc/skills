---
name: injective-rfq-quote
description: Provide liquidity as a market maker on Injective RFQ. Connect to MakerStream as a whitelisted maker, receive RFQ requests, sign quotes with EIP-712 v2, and stream them back to takers. Use when the user is operating an MM bot, building maker tooling, or testing the maker side of an RFQ flow. Covers the canonical decimal form trap, the full SignQuote typed-data layout, settlement update subscriptions, and the v2 signing helper. Testnet-only — mainnet rollout TBA. Pairs with `injective-rfq-mm-onboarding` (whitelist + AuthZ setup) and `injective-rfq-autosign` (contract AuthZ grants).
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective RFQ Quote Skill (maker)

> **Testnet-only.** RFQ is not on mainnet yet; rollout TBA.

## Overview

Provide liquidity as a market maker on Injective RFQ:

1. Open a MakerStream WebSocket with `maker_address` set so you only see requests routed to you (and the broadcast set for whitelisted MMs).
2. For each incoming `CreateRFQRequestType`, decide your price + quantity, sign the quote with EIP-712 v2, send it back on the same stream.
3. Subscribe to `quote_update` and `settlement_update` events to track which of your quotes won and how the resulting fills landed.

Reference end-to-end: [`InjectiveLabs/rfq-testing`](https://github.com/InjectiveLabs/rfq-testing) → `examples/python-mm/main-grpc.py` (gRPC variant) and `examples/python-mm/main.py` (WebSocket variant). Python library helpers in `src/rfq_test/crypto/eip712.py` and `src/rfq_test/clients/websocket.py::MakerStreamClient`.

## Prerequisites

- **Whitelisted maker registration** — an admin must call `register_makers` on the RFQ contract for your maker address. See `injective-rfq-mm-onboarding` for the one-shot setup.
- **AuthZ grants** to the RFQ contract — both `MsgSend` and `MsgPrivilegedExecuteContract`, `expiration: null`, `GenericAuthorization`. See `injective-rfq-autosign`.
- **USDC + INJ balances** in the maker subaccount (USDC for margin, INJ for gas).
- `rfq-testing` library installed.

## Endpoints (testnet)

| | |
|---|---|
| Cosmos chain ID | `injective-888` |
| EVM chain ID (EIP-712 domain) | `1439` |
| RFQ contract | `inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk` |
| MakerStream WSS | `wss://testnet.rfq.ws.injective.network/injective_rfq_rpc.InjectiveRfqRPC/MakerStream` |

## EIP-712 v2 signing — what's actually signed

The v2 protocol uses a custom typed-data layout (NOT `eth_signTypedData_v4`):

- **Domain**: `EIP712Domain(string name, string version, uint256 chainId, address verifyingContract)`
  - `name = "RFQ"`, `version = "1"`
  - `chainId` = EVM chain ID (1439 testnet, 1776 mainnet)
  - `verifyingContract` = `bech32_to_evm(contract_bech32)` — 20 bytes from the bech32 address
- **`SignQuote` typed data** — 15 fields, each a 32-byte word. Decimals hashed as `keccak256(utf8(s))`; addresses left-padded to 32 bytes. Final digest is `keccak256(0x19 || 0x01 || domainSep || msgHash)`, signed with secp256k1 raw — no EIP-191 prefix, no JSON canonicalization.

Use the library helper. Don't roll your own digest unless you also want to maintain it:

```python
from rfq_test.crypto.eip712 import sign_quote_v2

signature = sign_quote_v2(
    private_key=mm_private_key,
    evm_chain_id=evm_chain_id,                   # config.signing_context_v2[0]
    verifying_contract_bech32=contract,           # config.signing_context_v2[1]
    market_id=request.market_id,
    rfq_id=int(request.rfq_id),
    taker=request.request_address,
    direction=request.direction,                  # taker's direction (NOT MM's quoted side)
    taker_margin=request.margin,
    taker_quantity=request.quantity,
    maker=mm_inj_address,
    maker_subaccount_nonce=0,
    maker_quantity=quote_qty,
    maker_margin=quote_margin,
    price=quote_price,                            # canonical decimal — see below
    expiry_ms=int(time.time() * 1000) + 20_000,
)
```

Returns `0x`-prefixed `r||s||v` hex (65 bytes).

## Decimal canonicalization (the BTC `76462.0` trap)

Every decimal field is hashed as `keccak256(utf8(s))`. `"4.5"` and `"4.50"` produce different digests, and the indexer rejects non-canonical strings outright with `quote_failed: <field> "76462.0": not in canonical decimal form`.

Run every decimal field through this helper before signing AND before putting it on the wire — they MUST be byte-identical:

```python
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR

def to_canonical(x, tick, rounding=ROUND_FLOOR) -> str:
    return format(
        Decimal(str(x)).quantize(Decimal(str(tick)), rounding=rounding).normalize(),
        "f",
    )

def canonical_decimal(x) -> str:
    return format(Decimal(str(x)).normalize(), "f")

# 4.50      → "4.5"     (any fractional tick)
# 76462.0   → "76462"   (BTC perp, tick "1")
# 110.00    → "110"     (INJ perp, tick "0.01")
```

Pull `min_price_tick_size` and `min_quantity_tick_size` from `injective-derivatives-market-data`.

### Direction-aware rounding for the MM's quote price

| Taker direction | MM fills | Round | Reason |
|---|---|---|---|
| `long` (taker buys) | sell side | `ROUND_FLOOR` | stay ≤ taker's `worst_price` |
| `short` (taker sells) | buy side | `ROUND_CEILING` | stay ≥ taker's `worst_price` |

For quantities, always `ROUND_FLOOR` — never quote more than the taker asked for.

## Workflow

### 1. Connect with maker subscriptions

```python
from rfq_test.config import get_environment_config
from rfq_test.crypto.wallet import Wallet
from rfq_test.clients.websocket import MakerStreamClient
import os

env = get_environment_config()
mm = Wallet.from_private_key(os.environ["TESTNET_MM_PRIVATE_KEY"])
chain_id, contract = env.signing_context
evm_chain_id, _    = env.signing_context_v2

client = MakerStreamClient(
    env.indexer.ws_endpoint,
    maker_address=mm.inj_address,
    subscribe_to_quotes_updates=True,             # status=accepted/rejected per quote
    subscribe_to_settlement_updates=True,         # full settlement when a quote of yours fills
)
await client.connect()
```

### 2. Receive a request, decide pricing, send the quote

```python
request = await client.wait_for_request(timeout=30)

# Pull mark price + tick (cache per session); spread = your edge
mark = await price_fetcher.get_mark_price(request.market_id)
spread = mark * Decimal("0.005")                  # 50 bps example
if request.direction == "long":
    raw_price = mark + spread
    price_rounding = ROUND_FLOOR
else:
    raw_price = mark - spread
    price_rounding = ROUND_CEILING

quote_price = to_canonical(raw_price, price_tick, rounding=price_rounding)

request_margin = Decimal(request.margin)
request_qty    = Decimal(request.quantity)
quote_qty      = to_canonical(min(your_capacity, request_qty), qty_tick)

if Decimal(quote_qty) == request_qty:
    quote_margin = request.margin
else:
    quote_margin = canonical_decimal(request_margin * Decimal(quote_qty) / request_qty)

expiry = int(time.time() * 1000) + 20_000          # 20s validity (live MM); keep ≥ 2s

sig = sign_quote_v2(
    private_key=mm.private_key,
    evm_chain_id=evm_chain_id,
    verifying_contract_bech32=contract,
    market_id=request.market_id,
    rfq_id=int(request.rfq_id),
    taker=request.request_address,
    direction=request.direction,
    taker_margin=request.margin,
    taker_quantity=request.quantity,
    maker=mm.inj_address,
    maker_subaccount_nonce=0,
    maker_quantity=quote_qty,
    maker_margin=quote_margin,
    price=quote_price,
    expiry_ms=expiry,
)

await client.send_quote({
    "rfq_id": int(request.rfq_id),
    "market_id": request.market_id,
    "taker_direction": request.direction,
    "margin": quote_margin,
    "quantity": quote_qty,
    "price": quote_price,
    "expiry": expiry,
    "maker": mm.inj_address,
    "taker": request.request_address,
    "signature": sig,
    "maker_subaccount_nonce": 0,
    "sign_mode": "v2",                            # required on the wire
    "chain_id": chain_id,
    "contract_address": contract,
})
```

### 3. Watch the result

- `quote_update` event for each of your quotes:
  - `status="accepted"` — your quote was used in settlement
  - `status="rejected"` — included in evaluation but not picked
  - `executed_quantity`, `executed_margin` — the actual filled portion
- `settlement_update` event when a settlement includes any quote of yours.

These let you reconcile quotes against fills and update your inventory model.

## Common errors

| Error contains | Cause | Fix |
|---|---|---|
| `not in canonical decimal form` | Trailing zero / `.0` on integer / scientific notation in a decimal field | Run every decimal through `to_canonical(x, tick)` |
| `signature does not match maker address` (v2) | Signed string ≠ wire string, or wrong taker direction encoded, or wrong domain (chain id / contract) | Pass `request.direction` (the taker's) to `sign_quote_v2`; never pre-format separately for sign vs wire |
| `must be one of "v1", "v2"` | `sign_mode` empty on the wire | Set `"v2"` (the library default) |
| `quote duplicated` / `already submitted` | Same maker submitted twice for same `rfq_id` | One quote per `(maker, rfq_id)` — wait for the next request |
| `maker not registered` | Whitelist registration not done | `injective-rfq-mm-onboarding` |
| `quote price outside slippage band` | Quoted price worse than `mark ± 10%` | Tighten spread or skip the request |

## See also

- [`injective-rfq-trade`](../injective-rfq-trade/) — the taker side; what your quote is being matched against.
- [`injective-rfq-conditional-order`](../injective-rfq-conditional-order/) — TP/SL flow you may need to handle as an MM (quotes against intent-driven RFQs).
- [`injective-rfq-autosign`](../injective-rfq-autosign/) — RFQ contract AuthZ grants.
- [`injective-rfq-mm-onboarding`](../injective-rfq-mm-onboarding/) — first-time MM setup (whitelist + grants + smoke test).
- [`injective-derivatives-market-data`](../injective-derivatives-market-data/) — tick sizes, oracle marks, fees.
