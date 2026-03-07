---
name: injective-funding
description: Mass fund Injective wallets with INJ and USDT. Batch bank transfers (MsgSend), deposit to exchange subaccounts, top up taker wallets, and check balances across many wallets. Supports batching 200+ transfers in a single transaction. Supports batching 200+ transfers in a single transaction.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective Mass Funding Skill

## Overview

Fund many Injective wallets efficiently. Batch bank transfers, deposit to exchange subaccounts, and verify balances. Based on an Injective RFQ test framework.

## Reference Code

- **Seed-based funding**: `scripts/fund_subaccounts.py`
- **Two-step USDT funding**: `scripts/fund_demo_subaccounts.py`
- **Generate + fund 100 wallets**: `scripts/setup_wallets.py`
- **Top up takers**: `scripts/top_up_demo.py`
- **Bank to subaccount deposit**: `scripts/move_to_sub.py`
- **Balance checks**: `scripts/check_balances.py`, `scripts/check_all_balances.py`, `scripts/check_funding.py`

## Batch Bank Transfers

### 200 Transfers in One Transaction
From `setup_wallets.py` — batch up to 200 `MsgSend` in a single tx:
```python
from pyinjective.composer import Composer
from pyinjective.transaction import Transaction

composer = Composer(network=network.string())
msgs = []

for wallet in wallets:
    # Send INJ
    msgs.append(composer.msg_send(
        sender=funder_address,
        receiver=wallet.inj_address,
        amount=inj_amount,  # in wei (1e18)
        denom="inj"
    ))
    # Send USDT
    msgs.append(composer.msg_send(
        sender=funder_address,
        receiver=wallet.inj_address,
        amount=usdt_amount,  # in 1e6
        denom=usdt_denom
    ))

# Build and broadcast single tx with all msgs
tx = Transaction(msgs=msgs, ...)
```

### USDT Denoms by Network
| Network | USDT Denom | Decimals |
|---------|-----------|----------|
| Mainnet | `peggy0xdAC17F958D2ee523a2206206994597C13D831ec7` | 6 |
| Testnet | `peggy0x87aB3B4C8661e07D6372361211B96ed4Dc36B1B5` | 6 |
| Devnet | varies per config | 6 |

### INJ Amounts
INJ uses 18 decimals (like ETH wei):
- 1 INJ = `1000000000000000000` (1e18)
- 0.1 INJ = `100000000000000000` (1e17)

## Subaccount Deposits

After funding bank accounts, move to exchange subaccounts for trading:

```python
from pyinjective.core.broadcaster import MsgBroadcasterWithPk

msg = composer.msg_subaccount_deposit(
    sender=address,
    subaccount_id=get_subaccount_id(address, nonce=0),
    amount=Decimal(str(amount)),
    denom=denom
)

broadcaster = MsgBroadcasterWithPk.new_using_simulation(
    network=network,
    private_key=private_key
)
await broadcaster.broadcast([msg])
```

### Subaccount ID Calculation
```python
def get_subaccount_id(inj_address: str, nonce: int = 0) -> str:
    """Generate subaccount ID: eth_address + nonce (padded to 24 hex chars)"""
    eth_addr = inj_to_eth_address(inj_address)
    return eth_addr.lower() + format(nonce, '024x')
```

## Two-Step USDT Funding (Testnet Pattern)

1. **Parent sends USDT to child** via bank `MsgSend`
2. **Child deposits USDT** from bank to exchange subaccount

This is needed because on testnet, the faucet only gives INJ, not USDT. You need to pre-fund a parent wallet with USDT.

## Balance Checks

### Bank Balance
```python
balance = await client.fetch_bank_balance(address, denom)
# Returns {"balance": {"denom": "...", "amount": "..."}}
```

### Subaccount Balance
```python
deposits = await client.fetch_subaccount_deposits(subaccount_id)
# Returns available + total deposits per denom
```

### Funding Verification Script
```bash
# Check if all wallets are properly funded
python scripts/check_funding.py
# Shows: funder balance, per-wallet bank balance, per-wallet subaccount balance
```

## CLI Patterns

```bash
# Fund 20 MM + 80 retail from seed phrases (devnet)
python scripts/fund_subaccounts.py --env devnet0 --count 20 --amount 10

# Fund only MMs
python scripts/fund_subaccounts.py --env testnet --count 20 --mm-only --amount 5

# Generate 100 fresh wallets + fund them
python scripts/setup_wallets.py

# Move all bank USDT to subaccounts
python scripts/move_to_sub.py

# Top up 10 retail takers with 100 USDT each
python scripts/top_up_demo.py
```

## Key Facts
- Max ~200 msgs per transaction (gas limit)
- Use `MsgBroadcasterWithPk.new_using_simulation()` for auto gas estimation
- Sequence mismatch errors are common in rapid-fire txs -- add retry logic
- Always verify with `check_balances.py` after funding
- Funder wallet needs enough INJ for gas + enough tokens for all transfers

## Dependencies
- `injective-py>=1.12.0`
- `httpx>=0.27`
- Python >= 3.11
