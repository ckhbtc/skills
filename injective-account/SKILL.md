---
name: injective-account
description: Analyze any Injective wallet address. Query bank balances across all token types (INJ, USDT, IBC assets, Peggy ERC-20s), inspect trading subaccount balances, and view open perpetual positions with unrealized P&L. Useful for portfolio monitoring, position management, and pre-trade checks. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective Account Skill

## Overview

Query balances and open positions for any Injective address. No signing required — all reads are public.

## Tools

### account_balances
Returns bank + subaccount balances for an address.

```
account_balances
  address: inj1...
  denom: usdt         ← optional: filter to one token
```

Returns:
- `bankBalances[]` — wallet-level balances (all denoms or filtered)
- `subaccountBalances[]` — per-subaccount trading balances
  - `subaccountId` — 0x... hex ID
  - `denom` — token denom
  - `deposit.totalBalance` — total (available + in orders)
  - `deposit.availableBalance` — free to trade

### account_positions
Returns open perpetual positions with P&L.

```
account_positions
  address: inj1...
  market: BTC         ← optional: filter by symbol
```

Returns per position:
- `market` — symbol (BTC, ETH, etc.)
- `direction` — long | short
- `quantity` — contracts held
- `entryPrice` — average entry in USDT
- `markPrice` — current oracle price
- `unrealizedPnl` — USDT P&L at mark price
- `margin` — posted margin
- `leverage` — effective leverage

### token_metadata
Resolve any denom to human-readable metadata.

```
token_metadata
  denom: peggy0xdac17f958d2ee523a2206206994597c13d831ec7
```

Returns: `{ symbol, name, decimals, type, peggyDenom }`

## Common Workflows

### "What's my balance?"
```
account_balances(address: inj1...)
→ show bankBalances + subaccountBalances summary
```

### "Do I have enough USDT to trade?"
```
account_balances(address: inj1..., denom: usdt)
→ check subaccountBalances[0].deposit.availableBalance
```
If bank balance has USDT but subaccount doesn't: use `subaccount_deposit` to move funds in.

### "Show my positions and P&L"
```
account_positions(address: inj1...)
→ display each position with entry vs mark price and unrealizedPnl
```

### "What's my total portfolio value?"
```
account_balances    → sum all balances in USD equivalent
account_positions   → add unrealized P&L
```

## Denom Format Reference

| Type | Format | Example |
|---|---|---|
| Native | `inj` | INJ |
| Peggy (bridged ERC-20) | `peggy0x...` | USDT (`peggy0xdac17...`) |
| IBC | `ibc/HASH` | ATOM |
| TokenFactory | `factory/inj.../name` | — |
| inEVM ERC-20 | `erc20:0x...` | — |

Use `token_metadata` to resolve any denom to a human-readable symbol.

## Subaccount IDs

Injective uses subaccounts for isolated margin. The default subaccount index is 0:
- `subaccountId = address + "000000000000000000000000" + "0".padStart(24, "0") + "0000"`
- In practice, the MCP tools default to subaccount index 0 automatically.
- Advanced users can specify `subaccountId` explicitly on trade tools.
