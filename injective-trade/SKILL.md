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
  - EIP-712: MetaMask-compatible; same secp256k1 key, signs EIP-712 typed data
- **Slippage**: Market orders use oracle price ± slippage. Default: 1% open, 5% close.
- **Fees**: Injective charges 0 gas for trading. Taker fee ~0.1%, maker fee ~0.05%.

## EIP-712 Browser Signing — Critical Notes

These apply when implementing `tx.ts` / `openTrade()` / `closeTrade()` in a browser frontend:

### SDK Version
Pin to exactly `1.17.8` — do NOT use `^1.17.8`:
```json
"@injectivelabs/sdk-ts": "1.17.8",
"@injectivelabs/networks": "1.17.8",
"@injectivelabs/ts-types": "1.17.8"
```
Versions 1.18+ have breaking changes that cause signature verification failure on Injective mainnet.

### Chain ID requirement
MetaMask must be on **Ethereum mainnet (1)** or **Injective EVM (2525)**.
Any other chain (Arbitrum=42161, custom chains, etc.) will broadcast but fail with:
`"signature verification failed: unable to verify signer signature of EIP712 typed data"`

Add a guard before signing:
```typescript
const INJECTIVE_ACCEPTED_EVM_CHAINS: Record<number, string> = {
  1: 'Ethereum mainnet',
  2525: 'Injective EVM',
}
const chainId = parseInt(await window.ethereum.request({ method: 'eth_chainId' }), 16)
if (!INJECTIVE_ACCEPTED_EVM_CHAINS[chainId]) throw new Error(
  `Switch MetaMask to Ethereum mainnet or Injective EVM (2525) — chain ${chainId} not supported`
)
```

### Pass-through pattern (EasyPerps approach)
Read the active MetaMask chain and pass it to BOTH `getEip712TypedData` and `createWeb3Extension`.
**Never hardcode 2525** — MetaMask v11+ enforces that the EIP-712 domain chainId matches the active chain.

```typescript
const evmChainId = parseInt(
  await window.ethereum!.request({ method: 'eth_chainId' }) as string, 16
)
// Use evmChainId in BOTH calls:
const typedData = getEip712TypedData({ msgs: msg, tx: {...}, evmChainId })
const web3Extension = createWeb3Extension({ evmChainId })
```

### Fee must match between signed data and broadcast tx
**This is the #1 cause of "signature verification failed" errors.**
`getEip712TypedData` and `createTransaction` must use the EXACT same fee.
Without an explicit fee, `getEip712TypedData` uses the SDK default (`64000000000000 inj / 400000 gas`),
but `createTransaction` uses whatever you pass — if they differ, the hash changes and the signature is invalid.

```typescript
const TX_FEE = {
  amount: [{ denom: 'inj', amount: '200000000000000' }],
  gas: '1000000',
}

// Pass TX_FEE to BOTH:
const typedData = getEip712TypedData({ msgs, tx: {...}, fee: TX_FEE, evmChainId })
const { txRaw } = createTransaction({ ..., fee: TX_FEE })
```

### Tool schema for Claude
When defining browser tools for an AI to call:
- `trade_open`: use `notional_usdt` (not `amount`) — must match `executeBrowserTool` reads
- `trade_close`: **must include `side` and `quantity` as required fields** — Claude won't pass them otherwise and `closeTrade()` will receive `undefined`

```typescript
// trade_open required: ['symbol', 'side', 'notional_usdt', 'leverage']
// trade_close required: ['symbol', 'side', 'quantity']
```

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
