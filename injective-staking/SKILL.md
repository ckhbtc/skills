---
name: injective-staking
description: Query and manage Injective staking delegations, rewards, and validator info. Look up staker addresses, delegation amounts, unbonding status, and claimed rewards via Injective LCD/REST API.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective Staking Skill

## Overview

Query Injective staking data via LCD REST API. Covers delegations, rewards, validators, and unbonding. Useful for treasury dashboards, staker audits, and validator monitoring.

## Endpoints

All endpoints use Injective LCD REST API. Mainnet: `https://lcd.injective.network`

### Query Delegations for an Address
```
GET /cosmos/staking/v1beta1/delegations/{delegator_addr}
```
Returns all active delegations with validator address and shares.

### Query Delegation to Specific Validator
```
GET /cosmos/staking/v1beta1/validators/{validator_addr}/delegations/{delegator_addr}
```

### Query Unbonding Delegations
```
GET /cosmos/staking/v1beta1/delegators/{delegator_addr}/unbonding_delegations
```

### Query Staking Rewards
```
GET /cosmos/distribution/v1beta1/delegators/{delegator_addr}/rewards
```
Returns pending (unclaimed) rewards per validator and total.

### Query Validators
```
GET /cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED&pagination.limit=100
```

### Query Single Validator
```
GET /cosmos/staking/v1beta1/validators/{validator_addr}
```

### Query Staking Parameters
```
GET /cosmos/staking/v1beta1/params
```
Returns unbonding time, max validators, bond denom (inj).

## Key Facts

- **Decimals**: All amounts in `inj` denom use 1e18 (like ETH wei)
- **Unbonding period**: 21 days on Injective mainnet
- **Rewards**: Must be claimed via `MsgWithdrawDelegatorReward`. Track claimed vs accrued separately
- **Delegation shares**: Not 1:1 with tokens. Use `validator.tokens / validator.delegator_shares` ratio
- **Slashing**: Check `signing_infos` for validator jail status

## Common Tasks

### Check total staked INJ for a wallet
```bash
curl -s "https://lcd.injective.network/cosmos/staking/v1beta1/delegations/inj1..." | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = sum(int(d['balance']['amount']) for d in data.get('delegation_responses', []))
print(f'{total / 1e18:.2f} INJ staked')
"
```

### Find all stakers with > N INJ delegated
Use the archival node endpoints for historical queries:
- Tendermint RPC: `https://tm.injective.network:443`
- LCD REST: `https://lcd.injective.network`
- gRPC: `grpc.injective.network:443`

Query validators first, then iterate delegations per validator. Note: pagination required (default limit 100).

### Check pending rewards
```bash
curl -s "https://lcd.injective.network/cosmos/distribution/v1beta1/delegators/inj1.../rewards"
```

## Python SDK Pattern (injective-py)
```python
from pyinjective.async_client import AsyncClient
from pyinjective.core.network import Network

async def get_delegations(address: str):
    network = Network.mainnet()
    client = AsyncClient(network)
    delegations = await client.fetch_delegations(delegator_addr=address)
    return delegations
```
