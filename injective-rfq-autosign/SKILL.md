---
name: injective-rfq-autosign
description: Set up AuthZ delegation for trading via the Injective RFQ contract. Grants `MsgSend` + `MsgPrivilegedExecuteContract` to the RFQ contract address with `expiration: null` and `GenericAuthorization`, so quotes / accept-quote / signed-intent flows can settle without a wallet popup per tx. Distinct from `injective-orderbook-autosign`: the RFQ flow uses the CosmWasm contract's privileged execute path, not the exchange-module message types. Both MM and Retail need both grants. Mainnet RFQ contract: `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k`; testnet examples remain available.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective RFQ AutoSign Skill

> **Mainnet RFQ contract:** `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k`. Testnet examples below still use testnet endpoints.

## Overview

Trading via the Injective RFQ contract requires the wallet to grant `AuthZ` permissions to the contract address, so the contract can execute privileged messages on the wallet's behalf during settlement (move USDC margin, post the derivative trade, etc.). Without these grants, `accept_quote` and `accept_signed_intent` fail with `authorization not found`.

This skill is the RFQ-specific cousin of `injective-orderbook-autosign`: same AuthZ mechanism, but a different set of message types and a different grantee (the contract address, not an ephemeral session key).

## What gets granted

Two grants per role, both mandatory:

| Message type | Why |
|---|---|
| `/cosmos.bank.v1beta1.MsgSend` | Move USDC margin between subaccounts during settlement |
| `/injective.exchange.v2.MsgPrivilegedExecuteContract` | Let the RFQ contract execute the derivative-trade messages atomically |

Both **MM and Retail** need both grants. A common mistake is granting only `MsgSend` for retail — the contract also needs `MsgPrivilegedExecuteContract` to actually settle the trade.

## Why these specific grants (and not the orderbook ones)

The RFQ contract settles a trade by calling `MsgPrivilegedExecuteContract` against the exchange module — the contract is the privileged executor, not the user. The user's wallet doesn't sign each on-chain trade message; it signs only the `accept_quote` (or pre-signs the `SignedTakerIntent`) and grants the contract the right to do the rest.

`injective-orderbook-autosign` grants `MsgCreateDerivativeMarketOrder` / similar exchange-module types to an ephemeral session key. Different mechanism — same AuthZ primitive, different scope.

## Critical pitfalls

### 1. Use gas heuristics, not simulation

Gas simulation underestimates gas for grant transactions on some chains, causing panic / out-of-gas. Always use heuristics:

```python
from pyinjective.core.broadcaster import MsgBroadcasterWithPk

# DO:
broadcaster = MsgBroadcasterWithPk.new_using_gas_heuristics(
    network=network,
    private_key=private_key,
)

# DON'T:
# broadcaster = MsgBroadcasterWithPk.new_using_simulation(...)
```

### 2. `GenericAuthorization`, not `SendAuthorization`

The RFQ contract expects `GenericAuthorization` even for `MsgSend`. Don't use `SendAuthorization` with spend limits — the contract's verification rejects it.

### 3. `expiration: null` (permanent grants)

The contract expects grants with no expiration. The `pyinjective` `msg_grant_generic()` helper *requires* an expiration, so you have to build the grant manually:

```python
from pyinjective.proto.cosmos.authz.v1beta1 import authz_pb2, tx_pb2 as authz_tx_pb2
from google.protobuf import any_pb2

def create_grant_msg(granter: str, grantee: str, msg_type: str):
    """Build MsgGrant with expiration: null."""
    generic_authz = authz_pb2.GenericAuthorization()
    generic_authz.msg = msg_type

    authz_any = any_pb2.Any()
    authz_any.type_url = "/cosmos.authz.v1beta1.GenericAuthorization"
    authz_any.value = generic_authz.SerializeToString()

    grant = authz_pb2.Grant()
    grant.authorization.CopyFrom(authz_any)
    # Do NOT set grant.expiration — that's what gives expiration: null

    grant_msg = authz_tx_pb2.MsgGrant()
    grant_msg.granter = granter
    grant_msg.grantee = grantee
    grant_msg.grant.CopyFrom(grant)
    return grant_msg
```

### 4. Always check `tx_response.code == 0`

A successful tx hash alone is not proof of success. Check:

```python
result = await broadcaster.broadcast([grant_msg])
tx_response = result.txResponse
if getattr(tx_response, "code", 0) != 0:
    raise Exception(f"Tx failed: {getattr(tx_response, 'rawLog', '')}")
```

## Reference flow

End-to-end script: `InjectiveLabs/rfq-testing` → `scripts/setup_authz_grants.py`. Idempotent — re-running won't error if the grants already exist (just no-ops).

## Workflow

```python
import asyncio, os
from pyinjective.async_client import AsyncClient
from pyinjective.core.network import Network
from pyinjective.core.broadcaster import MsgBroadcasterWithPk
from pyinjective.wallet import PrivateKey

CONTRACT = "inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk"   # testnet RFQ contract
MSG_TYPES = [
    "/cosmos.bank.v1beta1.MsgSend",
    "/injective.exchange.v2.MsgPrivilegedExecuteContract",
]

async def grant_all(private_key_hex: str, role: str):
    network = Network.testnet()
    pk = PrivateKey.from_hex(private_key_hex)
    granter = pk.to_public_key().to_address().to_acc_bech32()

    broadcaster = MsgBroadcasterWithPk.new_using_gas_heuristics(
        network=network, private_key=private_key_hex,
    )

    for msg_type in MSG_TYPES:
        grant_msg = create_grant_msg(granter, CONTRACT, msg_type)
        result = await broadcaster.broadcast([grant_msg])
        if getattr(result.txResponse, "code", 0) != 0:
            raise Exception(
                f"{role} grant of {msg_type} failed: {result.txResponse.rawLog}"
            )
        print(f"  ✓ {role}: granted {msg_type}")

async def main():
    await grant_all(os.environ["TESTNET_RETAIL_PRIVATE_KEY"], "retail")
    await grant_all(os.environ["TESTNET_MM_PRIVATE_KEY"],     "mm")

asyncio.run(main())
```

## Verifying grants on-chain

```bash
curl -s "https://testnet.sentry.lcd.injective.network/cosmos/authz/v1beta1/grants?granter=<INJ_ADDR>&grantee=inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk" | python3 -m json.tool
```

Expected: two grants, both `GenericAuthorization`, both with `expiration: null` and the message types above.

## Revoking

```python
# Build MsgRevoke for each msg_type, broadcast same way.
# Use case: rotating contract address, security audit, cleanup before mainnet.
```

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `authorization not found` (at `accept_quote` time) | One of the two grants is missing | Re-run the grant flow for both message types |
| `out of gas` (during grant tx) | Used `new_using_simulation()` | Switch to `new_using_gas_heuristics()` |
| `invalid expiration` | Built the grant with `pyinjective`'s default helper | Use the manual `create_grant_msg` above (no `expiration` field set) |
| `Tx hash returned but trade fails later` | Didn't check `tx_response.code` | Always inspect; rawLog has the cause |

## See also

- [`injective-rfq-trade`](../injective-rfq-trade/) — the taker flow that consumes these grants.
- [`injective-rfq-quote`](../injective-rfq-quote/) — the maker flow that consumes these grants.
- [`injective-rfq-mm-onboarding`](../injective-rfq-mm-onboarding/) — first-time MM setup; this is step 2.
- [`injective-orderbook-autosign`](../injective-orderbook-autosign/) — the parallel skill for orderbook trading (different message types).
- [`injective-authz-ops`](../injective-authz-ops/) — bulk-grant tooling across many wallets.
