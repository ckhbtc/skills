---
name: injective-bridge
description: Bridge tokens to and from Injective using deBridge DLN (fast, cross-chain) or Peggy (Ethereum canonical bridge). Supports inbound bridges from Arbitrum, Ethereum, Base, Polygon, BSC, Avalanche, and Optimism into Injective, and outbound bridges from Injective to any deBridge-supported chain. Get quotes before executing. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective Bridge Skill

## Overview

Move tokens cross-chain to/from Injective using two bridge protocols:
- **deBridge DLN** — fast (minutes), supports Arbitrum, Base, Ethereum, Polygon, BSC, Avalanche, Optimism
- **Peggy** — Injective's canonical Ethereum bridge (~30 min, decentralized)

Always get a quote first (`bridge_debridge_quote` / `bridge_debridge_inbound_quote`) before executing.

## Outbound: Injective → External Chain

### Step 1: Get a quote
```
bridge_debridge_quote
  address: inj1...         ← sender (Injective)
  srcTokenDenom: usdt      ← denom on Injective (symbol or full denom)
  amount: 50               ← human-readable amount
  dstChain: arbitrum       ← or: base, ethereum, polygon, bsc, avalanche, optimism
  dstTokenAddress: 0xaf88d065e77c8cc2239327c5edb3a432268e5831   ← USDC on Arbitrum
  recipient: 0x...         ← EVM address on destination chain
```

### Step 2: Execute
```
bridge_debridge_send
  address: inj1...
  password: ****
  srcTokenDenom: usdt
  amount: 50
  dstChain: arbitrum
  dstTokenAddress: 0xaf88...
  recipient: 0x...
```

## Inbound: External Chain → Injective

The Injective wallet's secp256k1 key signs on both chains (same private key works on EVM chains).

### Step 1: Get a quote
```
bridge_debridge_inbound_quote
  srcChain: arbitrum       ← or chain ID: 42161
  srcTokenAddress: 0xaf88d065e77c8cc2239327c5edb3a432268e5831   ← USDC on Arbitrum
  amount: 50
  dstTokenAddress: 0x88f7f2b685f9692caf8c478f5badf09ee9b1cc13   ← USDT on Injective EVM
  recipient: inj1...       ← or 0x EVM address on Injective
```

### Step 2: Execute (ERC20 approve + bridge tx on source chain)
```
bridge_debridge_inbound_send
  address: inj1...         ← Injective wallet (key used on source chain too)
  password: ****
  srcChain: arbitrum
  srcTokenAddress: 0xaf88...
  amount: 50
  dstTokenAddress: 0x88f7...
  recipient: inj1...
```

## Ethereum Canonical Bridge (Peggy)

For withdrawals to Ethereum only (slower but decentralized):
```
bridge_withdraw_to_eth
  address: inj1...
  password: ****
  denom: peggy0xdac17f958d2ee523a2206206994597c13d831ec7   ← USDT denom on Injective
  amount: 100
  ethRecipient: 0x...
```
Peggy takes ~30 minutes. No quote needed; fees are fixed in INJ.

## Chain Reference

| Chain | Name | Chain ID |
|---|---|---|
| Arbitrum | arbitrum | 42161 |
| Ethereum | ethereum | 1 |
| Base | base | 8453 |
| Polygon | polygon | 137 |
| BSC | bsc | 56 |
| Avalanche | avalanche | 43114 |
| Optimism | optimism | 10 |

## Common Token Addresses

**On Arbitrum:**
- USDC: `0xaf88d065e77c8cc2239327c5edb3a432268e5831`
- USDT: `0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9`

**On Ethereum:**
- USDC: `0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48`
- USDT: `0xdac17f958d2ee523a2206206994597c13d831ec7`

**On Injective EVM:**
- USDT: `0x88f7f2b685f9692caf8c478f5badf09ee9b1cc13`

## Notes

- deBridge DLN settles in minutes. Quote includes fee breakdown and estimated receive amount.
- The inbound flow reuses the Injective wallet's private key on the source EVM chain — this works because Injective uses the same secp256k1 curve as Ethereum.
- If the source chain has no configured default RPC, provide `rpcUrl` explicitly.
- After an inbound bridge, tokens arrive on Injective EVM. Use `subaccount_deposit` to move them into the trading subaccount.
