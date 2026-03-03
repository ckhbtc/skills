---
name: injective-token
description: Look up metadata for any Injective token or denom. Resolves native tokens (INJ), Peggy ERC-20 bridged tokens (USDT, USDC, WETH), IBC assets (ATOM, OSMO), TokenFactory tokens, and inEVM ERC-20s to their human-readable symbol, decimals, and type. Also supports sending tokens between addresses and depositing/withdrawing from trading subaccounts. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective Token Skill

## Overview

Resolve, inspect, and move tokens on Injective. Supports all Injective denom formats and handles token transfers between wallets and subaccounts.

## Token Lookup

### token_metadata
Resolve any denom to human-readable info.

```
token_metadata
  denom: peggy0xdac17f958d2ee523a2206206994597c13d831ec7
```

Returns:
- `symbol` — e.g. USDT
- `name` — Tether USD
- `decimals` — 6
- `type` — peggy | ibc | native | factory | erc20
- `peggyDenom` — ERC-20 contract address (Peggy tokens only)

## Token Transfers

### transfer_send
Send tokens to another Injective address.

```
transfer_send
  address: inj1...      ← sender (must be in keystore)
  password: ****
  to: inj1...           ← recipient
  denom: inj            ← token denom (or symbol shorthand)
  amount: 10            ← human-readable amount
```

### subaccount_deposit
Move tokens from bank wallet into a trading subaccount.

```
subaccount_deposit
  address: inj1...
  password: ****
  denom: usdt
  amount: 100
  subaccountIndex: 0    ← optional, default 0
```

### subaccount_withdraw
Move tokens from trading subaccount back to bank wallet.

```
subaccount_withdraw
  address: inj1...
  password: ****
  denom: usdt
  amount: 100
  subaccountIndex: 0
```

## Denom Reference

| Token | Denom | Decimals |
|---|---|---|
| INJ | `inj` | 18 |
| USDT | `peggy0xdac17f958d2ee523a2206206994597c13d831ec7` | 6 |
| USDC | `peggy0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48` | 6 |
| WETH | `peggy0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` | 18 |
| WBTC | `peggy0x2260fac5e5542a773aa44fbcfedf7c193bc2c599` | 8 |
| ATOM | `ibc/C4CFF46FD6DE35CA4CF4CE031E643C8FDC9BA4B99AE598E9B0ED98FE3A2319F9` | 6 |

For any unlisted token, use `token_metadata` with the full denom string.

## Common Workflows

### "What token is peggy0x...?"
```
token_metadata(denom: peggy0x...)
```

### "Send 5 INJ to a friend"
```
transfer_send(address: inj1me..., to: inj1friend..., denom: inj, amount: 5)
```

### "I have USDT in my wallet but can't trade"
USDT is in your bank balance, not your trading subaccount.
```
subaccount_deposit(address: inj1..., denom: usdt, amount: <amount>)
```

### "Move profits back to my wallet"
```
subaccount_withdraw(address: inj1..., denom: usdt, amount: <amount>)
```

## Notes

- Amounts are always in human-readable format (e.g. `1.5` for 1.5 USDT). The server handles decimal conversion internally.
- INJ has 18 decimals — never enter wei amounts; use `1.5` for 1.5 INJ.
- Token metadata is resolved against the on-chain Injective token registry and cached.
- IBC denoms are long hashes — use `token_metadata` to get the symbol before displaying to users.
