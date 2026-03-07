---
name: injective-authz-ops
description: Mass grant and manage AuthZ permissions on Injective. Grant generic authorizations for trading, bank sends, and contract execution to a grantee (e.g., RFQ contract). Includes idempotent bulk grants with pre-checks, retry logic, and verification. Includes idempotent bulk grants with pre-checks, retry logic, and verification.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective AuthZ Operations Skill

## Overview

Mass grant Cosmos SDK AuthZ permissions on Injective. Used to allow a smart contract or session key to execute transactions on behalf of wallets. Based on an Injective RFQ test framework.

## Reference Code

- **Mass grants (seed-based)**: `scripts/setup_authz_grants.py`
- **Mass grants (key-list)**: `scripts/grant_authz.py`
- **Shared library**: `src/rfq_test/utils/setup.py`
- **ChainClient grants**: `src/rfq_test/clients/chain.py` → `grant_authz()`, `query_authz_grants()`
- **MM registration**: `scripts/register_makers.py`, `scripts/whitelist_mm_standalone.py`

## AuthZ Grant Types

### For Market Makers
```python
MM_AUTHZ_GRANTS = [
    "/injective.exchange.v1beta1.MsgSend",  # Not cosmos.bank -- Injective subaccount send
    "/cosmwasm.wasm.v1.MsgExecuteContract",  # Or MsgPrivilegedExecuteContract
]
```

### For Retail/Takers
```python
RETAIL_AUTHZ_GRANTS = [
    "/cosmos.bank.v1beta1.MsgSend",
    "/cosmwasm.wasm.v1.MsgExecuteContract",
    "/injective.exchange.v1beta1.MsgBatchUpdateOrders",
    "/injective.exchange.v1beta1.MsgCreateDerivativeMarketOrder",
    "/injective.exchange.v1beta1.MsgCreateSpotMarketOrder",
]
```

## Granting AuthZ

### Single Wallet Grant
```python
from pyinjective.composer import Composer
from google.protobuf import any_pb2, timestamp_pb2

def msg_grant_generic(granter, grantee, msg_type, expiration=None):
    """Create a MsgGrant with GenericAuthorization."""
    grant = authz_pb2.Grant(
        authorization=any_pb2.Any(
            type_url="/cosmos.authz.v1beta1.GenericAuthorization",
            value=GenericAuthorization(msg=msg_type).SerializeToString()
        ),
        # expiration=None means permanent
    )
    return authz_pb2.MsgGrant(
        granter=granter,
        grantee=grantee,
        grant=grant,
    )
```

### Bulk Idempotent Grants
The `run_authz_for_wallets()` pattern:
1. Query existing grants for each wallet
2. Diff against required grants
3. Only submit missing grants
4. Verify after broadcast
5. Retry on sequence mismatch (up to 3 attempts)

```python
async def run_authz_for_wallets(chain_client, wallets, contract_address, msg_types, label):
    for wallet in wallets:
        existing = await chain_client.query_authz_grants(wallet.inj_address, contract_address)
        existing_types = {g["authorization"]["msg"] for g in existing.get("grants", [])}
        missing = [mt for mt in msg_types if mt not in existing_types]
        if not missing:
            print(f"  {label} {wallet.inj_address}: all grants exist, skipping")
            continue
        for msg_type in missing:
            await chain_client.grant_authz(wallet.private_key, contract_address, msg_type)
```

### Query Existing Grants
```python
GET /cosmos/authz/v1beta1/grants?granter={granter}&grantee={grantee}
```

## MM Registration (Contract Whitelist)

Separate from AuthZ -- this is contract-level registration:
```python
async def register_maker(self, admin_key, mm_address):
    msg = {
        "register_maker": {
            "maker": mm_address
        }
    }
    # Execute as contract admin via MsgExecuteContract
```

### Standalone Whitelist Tool
`scripts/whitelist_mm_standalone.py` — self-contained, no library dependency. Supports:
- `--check-only` flag
- Interactive and non-interactive modes
- Embedded network configs for devnet0/devnet3/testnet
- Paginated `is_maker_registered()` query

## CLI Patterns

```bash
# Grant authz for 20 MM + 80 retail wallets
python scripts/setup_authz_grants.py --env testnet --count 20

# Grant only for MMs
python scripts/setup_authz_grants.py --env testnet --count 20 --mm-only

# Register MMs on contract
python scripts/register_makers.py --env testnet --count 20 --dry-run
python scripts/register_makers.py --env testnet --count 20

# Check whitelist
python scripts/check_whitelists.py
```

## Key Facts
- Use `GenericAuthorization` (not `SendAuthorization`) for flexibility
- Permanent grants (no expiration) unless security requires it
- Sequence mismatch is common in bulk ops -- retry with fresh sequence
- Verify grants after broadcast (chain state may lag)
- Contract address varies per environment (check `configs/{env}.yaml`)

## Dependencies
- `injective-py>=1.12.0`
- `httpx>=0.27`
- Python >= 3.11
