---
name: injective-trade
description: Execute perpetual futures trades on Injective using natural language. Supports market orders (open/close long or short), limit orders (place, list, cancel), and both Cosmos signing and EIP-712 MetaMask-compatible signing. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective Trade Skill

## Overview

Execute perpetual futures trades on Injective via the MCP server. Supports market orders and limit orders with both Cosmos and EIP-712 signing paths.

## Prerequisites

- Injective MCP server connected (`injective-agent`)
- A wallet in the keystore (`wallet_list` to check, `wallet_generate` or `wallet_import` to add)
- USDT balance in the trading subaccount (`subaccount_deposit` to move funds in)

## Workflow

### 1. Check setup
```
wallet_list          → confirm wallet exists
account_balances     → confirm subaccount has USDT
market_list          → list available perp markets
market_price BTC     → get current oracle price
```

### 2. Open a position (market order)

**Cosmos signing** (keystore wallet + password):
```
trade_open
  address: inj1...
  password: ****
  market: BTC         ← symbol, e.g. BTC, ETH, INJ, SOL
  side: long | short
  amount: 100         ← USDT notional
  leverage: 5
  slippage: 0.01      ← optional, default 1%
```

**EIP-712 signing** (MetaMask / browser wallet):
```
trade_open_eip712
  address: inj1...    ← must match MetaMask account
  market: BTC
  side: long
  amount: 100
  leverage: 5
```

### 3. Close a position
```
trade_close / trade_close_eip712
  address: inj1...
  password: ****      ← Cosmos only
  market: BTC
  slippage: 0.05      ← close slippage default 5%
```

### 4. Limit orders
```
trade_limit_open      → place a limit order
  side: buy | sell
  price: 95000        ← limit price in USDT
  amount: 500         ← notional USDT
  leverage: 3

trade_limit_orders    → list open limit orders
trade_limit_close     → cancel by orderHash
trade_limit_states    → query order states by hash
```

## Key Details

- **Markets**: Use symbol shorthand (`BTC`, `ETH`, `INJ`). `market_list` shows all active markets.
- **Amount**: Always USDT notional (e.g. `amount: 100` = $100 position).
- **Leverage**: 1–20x depending on market. Check `market_list` for max leverage.
- **Signing paths**:
  - Cosmos: password required per call; signs via Cosmos tx with InjectiveTx wrapper
  - EIP-712: MetaMask-compatible; same secp256k1 key, signs EIP-712 typed data — no chain switch needed
- **Slippage**: Market orders use oracle price ± slippage. Default: 1% open, 5% close.
- **Fees**: Injective charges 0 gas for trading. Taker fee ~0.1%, maker fee ~0.05%.

## Example Conversation

> "Open a $200 long on ETH with 3x leverage"
→ `trade_open(market: ETH, side: long, amount: 200, leverage: 3, ...)`

> "Place a limit buy on BTC at $90,000 for $500 notional, 5x"
→ `trade_limit_open(side: buy, price: 90000, amount: 500, leverage: 5, ...)`

> "Show my open orders"
→ `trade_limit_orders(address: inj1...)`

> "Cancel all my BTC limit orders"
→ `trade_limit_orders` → iterate hashes → `trade_limit_close` for each

## References

See `references/tool-params.md` for full parameter schemas.
