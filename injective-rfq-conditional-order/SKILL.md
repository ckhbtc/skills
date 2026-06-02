---
name: injective-rfq-conditional-order
description: Pre-sign TP/SL conditional orders on Injective RFQ that fire automatically when the mark price crosses a trigger threshold. Sign a SignedTakerIntent with EIP-712 v2, submit via TakerStream `conditional_order` or REST `/v1/conditionalOrder`, and track the `epoch` / `lane_version` counters used for replay protection and cancellation. Use when the user wants take-profit or stop-loss on an open position without staying online to send the close. Reduce-only (`margin="0"`); supports `mark_price_gte`, `mark_price_lte`, and `immediate` triggers. Cancel via `CancelIntentLane` (per market) or `CancelAllIntents` (global). Mainnet RFQ contract: `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k`; testnet examples remain available.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective RFQ Conditional Order Skill (TP/SL signed intents)

> **Mainnet RFQ contract:** `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k`. Testnet examples below still use testnet endpoints.

## Overview

A conditional order is a pre-signed taker intent that the indexer monitors and fires automatically when a mark-price trigger crosses. Once fired, the indexer acts as the RFQ requester on the taker's behalf — collects quotes, picks one, and submits `accept_signed_intent` on-chain. The taker doesn't have to be online.

Use this for take-profit / stop-loss flows, especially overnight or while a strategy is unattended.

Reference end-to-end: [`InjectiveLabs/rfq-testing`](https://github.com/InjectiveLabs/rfq-testing) → `scripts/conditional_order_example.py` (full create / list / cancel flow). Library helper: `rfq_test.crypto.eip712.sign_conditional_order_v2`.

## Trigger semantics

| Trigger type | Fires when | Typical use |
|---|---|---|
| `mark_price_gte` | mark >= `trigger_price` | Take-profit for a long position; stop-loss for a short |
| `mark_price_lte` | mark <= `trigger_price` | Take-profit for a short position; stop-loss for a long |
| `immediate` | always (no wait) | Indexer-driven close-now via the same signed-intent path |

For `immediate`, pass `trigger_price="0"`. The digest binds that fixed `"0"` value for immediate orders.

## Reduce-only constraint

`margin` MUST be `"0"`. Conditional orders can only close existing positions; opening a new one through a signed intent is not supported. The contract enforces this.

## Replay protection: `epoch` and `lane_version`

Two on-chain counters guard against replays and let the taker invalidate previously-signed intents without sending an explicit cancel for each one.

| Counter | Bumped by | Scope | Effect |
|---|---|---|---|
| `lane_version` | `CancelIntentLane(market_id, subaccount_nonce)` | One `(taker, market_id, subaccount_nonce)` lane | Invalidates every intent for that lane signed with the old `lane_version` |
| `epoch` | `CancelAllIntents` | All markets, all subaccounts for the taker | Invalidates every intent for the taker signed with the old `epoch` |

Track both per-taker and increment after each on-chain cancel. Intents signed with stale counters are rejected.

## Prerequisites

- Testnet wallet with USDC margin and INJ for gas.
- AuthZ grants on the RFQ contract for `MsgSend` + `MsgPrivilegedExecuteContract`. See `injective-rfq-autosign`.
- An open position to close (the intent is reduce-only).
- `rfq-testing` library installed.

## Endpoints (testnet)

| | |
|---|---|
| Cosmos chain ID | `injective-888` |
| EVM chain ID (EIP-712 domain) | `1439` |
| Testnet RFQ contract | `inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk` |
| Mainnet RFQ contract | `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k` |
| TakerStream WSS | `wss://testnet.rfq.ws.injective.network/injective_rfq_rpc.InjectiveRfqRPC/TakerStream` |
| REST conditional-order endpoint | `POST {indexer_http_endpoint}/v1/conditionalOrder` |

## Workflow

### 1. Sign the intent

```python
from rfq_test.config import get_environment_config
from rfq_test.crypto.wallet import Wallet
from rfq_test.crypto.eip712 import sign_conditional_order_v2
import os, time

env = get_environment_config()                       # RFQ_ENV=testnet
chain_id, contract = env.signing_context
evm_chain_id, _    = env.signing_context_v2
retail = Wallet.from_private_key(os.environ["TESTNET_RETAIL_PRIVATE_KEY"])
market = env.markets[0]

rfq_id      = int(time.time() * 1000)                 # unique order ID — use ms timestamp
deadline_ms = rfq_id + 24 * 60 * 60 * 1000            # 24 h (max 30 d)

intent_sig = sign_conditional_order_v2(
    private_key=retail.private_key,
    evm_chain_id=evm_chain_id,
    verifying_contract_bech32=contract,
    version=1,
    taker=retail.inj_address,
    epoch=current_epoch,                              # track per-taker; start at 1
    lane_version=current_lane_version,                # track per-(taker,market,nonce); start at 1
    subaccount_nonce=0,
    rfq_id=rfq_id,
    market_id=market.id,
    deadline_ms=deadline_ms,
    direction="short",                                # closing a long → short
    quantity="1",                                     # canonical, quantized to qty tick
    margin="0",                                       # reduce-only
    worst_price="19.5",                               # canonical, quantized to price tick
    min_total_fill_quantity="1",
    trigger_type="mark_price_gte",                    # take-profit on a long
    trigger_price="20",                               # canonical
    cid=None,
    allowed_relayer=None,
)
```

Decimal fields follow the same canonicalization rule as quotes — see `injective-rfq-trade` for `to_canonical(x, tick)`. `mark_price_gte` and `mark_price_lte` digests bind the trigger price; `immediate` uses `"0"`.

### 2. Submit (TakerStream OR REST)

**TakerStream (WebSocket)** — same connection that handles regular RFQ requests:

```python
from rfq_test.clients.websocket import TakerStreamClient

async with TakerStreamClient(env.indexer.ws_endpoint,
                             request_address=retail.inj_address) as client:
    ack = await client.send_conditional_order(
        order_body={
            "version": 1, "chain_id": chain_id, "contract_address": contract,
            "taker": retail.inj_address, "epoch": current_epoch, "rfq_id": rfq_id,
            "market_id": market.id, "subaccount_nonce": 0,
            "lane_version": current_lane_version,
            "deadline_ms": deadline_ms, "direction": "short",
            "quantity": "1", "margin": "0", "worst_price": "19.5",
            "min_total_fill_quantity": "1",
            "trigger_type": "mark_price_gte", "trigger_price": "20",
            "unfilled_action": None, "cid": None, "allowed_relayer": None,
        },
        signature=intent_sig,
        wait_for_ack=True,
        # sign_mode="v2" is the library default; the wire field is conditional_order_sign_mode="v2"
    )
print(f"ACK: rfq_id={ack['rfq_id']} status={ack['status']}")
```

**REST** — single HTTP POST, same payload shape:

```python
import httpx
async with httpx.AsyncClient() as http:
    resp = await http.post(
        f"{env.indexer.http_endpoint.rstrip('/')}/v1/conditionalOrder",
        json={
            "order": order_body,
            "signature": intent_sig,
            "sign_mode": "v2",                        # required — mirror the digest version
        },
    )
    resp.raise_for_status()
```

### 3. List / verify active intents

```python
async with httpx.AsyncClient() as http:
    resp = await http.get(
        f"{env.indexer.http_endpoint.rstrip('/')}/conditionalOrders",
        params={"taker": retail.inj_address},
    )
    orders = resp.json()
```

### 4. Cancel

Two on-chain paths — bump the relevant counter, then increment locally so future intents use the new value.

**Per-market lane cancel:**

```python
from rfq_test.clients.contract import ContractClient

contract_client = ContractClient(env.contract, env.chain)
tx = await contract_client.cancel_intent_lane(
    private_key=retail.private_key,
    market_id=market.id,
    subaccount_nonce=0,
)
current_lane_version += 1                             # local bump for next intent
```

**Global cancel (all markets, all subaccounts):**

```python
tx = await contract_client.cancel_all_intents(private_key=retail.private_key)
current_epoch += 1
```

After either, every previously-signed intent for that scope becomes stale at the contract.

## Common errors

| Error contains | Cause | Fix |
|---|---|---|
| `epoch mismatch` / `stale epoch` | Local `epoch` out of sync with on-chain after a `CancelAllIntents` | Re-query and bump locally |
| `lane_version mismatch` | Same, for `CancelIntentLane` | Same |
| `not in canonical decimal form` | Trailing zero on a decimal field | Run through `to_canonical(x, tick)` |
| `must be one of "v1", "v2"` | `sign_mode` / `conditional_order_sign_mode` empty on the wire | Library defaults to `"v2"`; only fires if you bypassed it |
| `signature does not match request address` | Signed and wire data diverge, or wrong taker / epoch / lane_version, or wrong domain (chainId / contract) | Sanity-check that every field in the digest matches the wire body byte-for-byte |
| `margin must be "0"` | Tried to sign a non-zero margin (i.e. open-position intent) | Reduce-only only |
| `deadline_ms exceeds maximum` | Deadline > 30 days from creation | Cap at 30 days |
| `code 18: must contain at least one message` | Wire body missing one of: `version`, `chain_id`, `contract_address`, `taker`, `epoch`, `rfq_id`, `market_id`, `subaccount_nonce`, `lane_version`, `deadline_ms`, `direction`, `quantity`, `margin`, `worst_price`, `min_total_fill_quantity`, `trigger_type`, `trigger_price`, `unfilled_action`, `cid`, `allowed_relayer` | Send all 20 fields, even nullable ones (`unfilled_action`, `cid`, `allowed_relayer`) |

## See also

- [`injective-rfq-trade`](../injective-rfq-trade/) — direct (live) RFQ taker flow.
- [`injective-rfq-quote`](../injective-rfq-quote/) — maker side; quotes against fired intents the same way as live RFQs.
- [`injective-rfq-autosign`](../injective-rfq-autosign/) — AuthZ grants for the RFQ contract.
- [`injective-positions`](../injective-positions/) — manage the position you're protecting with the intent.
