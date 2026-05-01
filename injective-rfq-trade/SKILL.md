---
name: injective-rfq-trade
description: Take perpetual futures positions on Injective via RFQ — quote-based trading instead of the central orderbook. Sends an RFQ request, collects quotes from whitelisted market makers within a time window, picks the best by price, and accepts on-chain via the RFQ CosmWasm contract. Use when the user wants to take a derivative position via RFQ (often better fills on size than walking the orderbook) or when the orderbook lacks depth for the requested quantity. Testnet-only — mainnet rollout TBA. Pairs with `injective-rfq-autosign` (AuthZ grants for the RFQ contract) and `injective-derivatives-market-data` (tick sizes, oracle marks).
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective RFQ Trade Skill (taker)

> **Testnet-only.** RFQ is not on mainnet yet; rollout TBA.

## Overview

Take a position on an Injective derivatives market by requesting quotes from whitelisted market makers and accepting the best one on-chain — instead of walking the central orderbook.

The taker flow:

1. Open a TakerStream WebSocket and send a `CreateRFQRequestType` for `(market_id, direction, margin, quantity, worst_price)`.
2. The indexer fans the request out to every whitelisted MM. They sign quotes with EIP-712 v2 and stream them back.
3. Collect quotes within a window (typically 2–5s) until you have at least one acceptable quote.
4. Build a CosmWasm `accept_quote` message with one or more quotes (the contract walks the array in order, filling from each until your total quantity is covered) and broadcast.

Reference end-to-end: [`InjectiveLabs/rfq-testing`](https://github.com/InjectiveLabs/rfq-testing) → `examples/test_settlement.py` (single quote) and `examples/taker_multi_quote.py` (aggregate across MMs).

## Prerequisites

- **Testnet wallet** with USDC margin (`erc20:0x0C382e685bbeeFE5d3d9C29e29E341fEE8E84C5d`) and INJ for gas.
- **AuthZ grants** to the RFQ contract for `MsgSend` + `MsgPrivilegedExecuteContract`. See `injective-rfq-autosign` (or `rfq-testing/scripts/setup_authz_grants.py`) — both grants required, `expiration: null`, `GenericAuthorization`.
- **`rfq-testing` library** installed (`pip install -e .` from a clone) or the standalone reference scripts in `examples/ts-retail/`.
- **Market metadata** loaded — see `injective-derivatives-market-data` for `min_price_tick_size`, `min_quantity_tick_size`, oracle mark.

## Endpoints (testnet)

| | |
|---|---|
| Cosmos chain ID | `injective-888` |
| EVM chain ID (EIP-712 domain) | `1439` |
| RFQ contract | `inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk` |
| TakerStream WSS | `wss://testnet.rfq.ws.injective.network/injective_rfq_rpc.InjectiveRfqRPC/TakerStream` |

## Workflow

### 1. Open the TakerStream and send a request

```python
from rfq_test.config import get_environment_config
from rfq_test.crypto.wallet import Wallet
from rfq_test.clients.websocket import TakerStreamClient
from decimal import Decimal
import os, time, uuid

env = get_environment_config()                       # RFQ_ENV=testnet
chain_id, contract = env.signing_context
retail = Wallet.from_private_key(os.environ["TESTNET_RETAIL_PRIVATE_KEY"])
market = env.markets[0]                               # e.g. INJ/USDC PERP

async with TakerStreamClient(env.indexer.ws_endpoint,
                             request_address=retail.inj_address) as client:
    rfq_id_hint = str(uuid.uuid4())
    ack = await client.send_request({
        "client_id": rfq_id_hint,                     # MUST be a UUID; indexer assigns the actual rfq_id
        "market_id": market.id,
        "direction": "long",
        "margin": "200",                              # canonical decimal — see "Decimal canonicalization" below
        "quantity": "10",
        "worst_price": "15.5",                        # canonical; quantize to price tick
        "expiry": int(time.time() * 1000) + 300_000,
    }, wait_for_response=True)
    rfq_id = int(ack["rfq_id"])
```

### 2. Collect quotes within a window

```python
    quotes = await client.collect_quotes(rfq_id=rfq_id, timeout=5.0, min_quotes=1)
```

Each quote dict carries `maker`, `margin`, `price`, `quantity`, `expiry`, `signature` (hex `0x`-prefixed), and `sign_mode` (always `"v2"`).

### 3. Pick the best (or aggregate across multiple)

```python
    eligible = [q for q in quotes if Decimal(q["price"]) <= Decimal("15.5")]
    eligible.sort(key=lambda q: Decimal(q["price"]))
    best = eligible[0]
```

For multi-quote aggregation (cover requested size by walking N cheapest quotes in order), see `examples/taker_multi_quote.py`. The contract walks the `quotes` array in submission order, filling from each until the taker's total quantity is covered.

### 4. Accept on-chain

```python
from rfq_test.clients.contract import ContractClient
from rfq_test.models.types import Direction
from decimal import Decimal

contract_client = ContractClient(env.contract, env.chain)
tx = await contract_client.accept_quote(
    private_key=retail.private_key,
    quotes=[{
        "maker": best["maker"],
        "margin": best["margin"],
        "quantity": best["quantity"],
        "price": best["price"],                       # MUST be byte-identical to the signed price
        "expiry": best["expiry"],
        "signature": best["signature"],
        "sign_mode": best.get("sign_mode", "v2"),     # forward as-is; use v2 explicitly
    }],
    rfq_id=rfq_id,
    market_id=market.id,
    direction=Direction.LONG,
    margin=Decimal("200"),
    quantity=Decimal("10"),
    worst_price=Decimal("15.5"),
    unfilled_action={"market": {}},                   # see "Unfilled action" below
)
```

Check the tx response: `code == 0` means accepted. On non-zero, parse `rawLog` for the cause (signature, slippage, maker not registered, not enough quote depth, etc.).

## Decimal canonicalization

The indexer rejects non-canonical decimals on every request and quote field. `"15.50"` and `"15.5"` produce different EIP-712 digests, and the indexer enforces `keccak256(utf8(s))` over the maker's quote — so the wire price MUST equal the signed price byte-for-byte.

Run every decimal field (margin, quantity, worst_price, price, min_fill_quantity) through this helper before signing or sending:

```python
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR

def to_canonical(x, tick, rounding=ROUND_FLOOR) -> str:
    return format(
        Decimal(str(x)).quantize(Decimal(str(tick)), rounding=rounding).normalize(),
        "f",
    )

# 4.50      → "4.5"     (any fractional tick)
# 76462.0   → "76462"   (BTC perp, tick "1")
# 110.00    → "110"     (INJ perp, tick "0.01")
```

Symptom of getting this wrong: `quote_failed: <field> "76462.0": not in canonical decimal form (use plain notation without trailing zeros or scientific notation)`.

For request `worst_price`, round from the taker's perspective: long requests use `ROUND_CEILING` because it is the maximum price the taker will pay; short requests use `ROUND_FLOOR` because it is the minimum price the taker will accept. Quantities should always floor so the request never exceeds the intended size.

## Slippage band (worst_price ↔ oracle mark)

`worst_price` is the taker's price protection. Current testnet validation also rejects requests outside the configured mark-price band:

- **Long**: `worst_price ≤ mark × 1.10` (default 10% slippage cap)
- **Short**: `worst_price ≥ mark × 0.90`

Pull the mark from `injective-derivatives-market-data` (`market_price BTC`) and quantize to `min_price_tick_size` before signing.

## Unfilled action

If the requested quantity isn't fully covered by the selected quotes, the contract can:

- `{"market": {}}` — post the unfilled remainder as an IOC/market fallback on the orderbook, still bounded by `worst_price`.
- `{"limit": {"price": "<canonical>"}}` — post a resting limit order at that price.
- Omit / `null` — reject if not fully covered.

## Common errors

| Error contains | Cause | Fix |
|---|---|---|
| `not in canonical decimal form` | Trailing zero or `.0` on an integer | Run through `to_canonical(x, tick)` |
| `signature does not match maker address` | MM signed `"15.5"` but quote on wire has `"15.50"` (or vice versa) | Reject the quote — MM bug |
| `must be one of "v1", "v2"` | `sign_mode` field missing on the wire | Library default is `"v2"`; only fires if you bypassed it |
| `authorization not found` | AuthZ grants missing | Run `injective-rfq-autosign` |
| `worst_price exceeds slippage band` | `worst_price` outside `mark ± 10%` | Pull current mark, recompute |
| `code 18: must contain at least one message` | `quotes` array empty | Collect at least one valid quote before AcceptQuote |

## See also

- [`injective-rfq-quote`](../injective-rfq-quote/) — the maker side; how an MM signs and responds to your request.
- [`injective-rfq-conditional-order`](../injective-rfq-conditional-order/) — pre-sign TP/SL intents that fire automatically on mark price.
- [`injective-rfq-autosign`](../injective-rfq-autosign/) — AuthZ grants for the RFQ contract.
- [`injective-orderbook-trade`](../injective-orderbook-trade/) — alternative venue: place orders directly on the central orderbook.
- [`injective-positions`](../injective-positions/) — close / flatten existing positions (orderbook + RFQ).
