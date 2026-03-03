---
name: injective-x402
description: Set up and interact with x402 payment-gated APIs on Injective EVM. The x402 protocol uses HTTP 402 responses to gate API endpoints behind micropayments — clients sign an EIP-3009 authorization, a facilitator submits it on-chain. Use when building or consuming pay-per-query APIs priced in USDT on Injective EVM (chain ID 1776). References the x402-injective package.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective x402 Skill

## Overview

x402 is an HTTP payment protocol: a server returns `402 Payment Required` for protected endpoints; the client attaches a signed EIP-3009 payment authorization; the server settles on-chain via a facilitator. No approval transactions, no prior on-chain setup per payment.

**Injective EVM** (chain ID 1776, mainnet) is a first-class x402 target. USDT on Injective EVM is the payment token.

## Architecture

```
Client (AI agent or browser)
  → GET /api/data
  ← 402 + { scheme, asset, maxAmount, network: "eip155:1776" }

Client signs EIP-3009 transferWithAuthorization off-chain
  → GET /api/data + X-PAYMENT header (signed auth)

Server verifies + settles via facilitator
  → 200 + data
```

## Package

```bash
npm install @x402/injective
```

Source: `/Users/ck/dev/x402/packages/x402-injective/`

## Server: Protect an Endpoint

```ts
import express from 'express'
import { injectivePaymentMiddleware } from '@x402/injective/middleware'
import { INJECTIVE_MAINNET_CAIP2 } from '@x402/injective/networks'

const app = express()

app.use(
  injectivePaymentMiddleware(
    {
      'GET /api/market-data': {
        description: 'Real-time Injective market data',
        mimeType: 'application/json',
        accepts: [{
          network: INJECTIVE_MAINNET_CAIP2,      // 'eip155:1776'
          asset: USDT_INJECTIVE_EVM,             // 0x... USDT on inEVM
          maxAmountRequired: '1000',             // 0.001 USDT (6 decimals)
          maxTimeoutSeconds: 60,
        }],
      },
    },
    {
      facilitator: { privateKey: process.env.PRIVATE_KEY },
      baseUrl: process.env.BASE_URL,
    }
  )
)
```

## Client: Pay for a Request

```ts
import { createInjectiveClient } from '@x402/injective/client'

const client = createInjectiveClient({
  privateKey: '0x...',       // payer wallet
  network: 'mainnet',
})

const response = await client.fetch('https://api.example.com/api/market-data')
const data = await response.json()
```

The client automatically:
1. Makes initial request, receives 402
2. Signs EIP-3009 authorization for the required amount
3. Retries with `X-PAYMENT` header
4. Returns the 200 response

## WrappedUSDT (WUSDT)

Native USDT on Injective EVM is a plain ERC-20 and does not implement EIP-3009 (required for x402). The `WrappedUSDT` contract adds a 1:1 EIP-3009 wrapper.

```ts
// Wrap USDT → WUSDT (one-time setup per user)
await usdtContract.approve(WUSDT_ADDRESS, amount)
await wusdtContract.deposit(amount)

// Use WUSDT_ADDRESS as the `asset` in x402 payment requirements
```

Contract source: `/Users/ck/dev/x402/packages/x402-injective/contracts/WrappedUSDT.sol`
Deploy script: `/Users/ck/dev/x402/examples/scripts/deploy-wrapped-usdt.ts`

## Injective EVM Network Config

| Property | Value |
|---|---|
| Chain ID | 1776 (mainnet), 1439 (testnet) |
| CAIP-2 | `eip155:1776` / `eip155:1439` |
| RPC (mainnet) | `https://inevm.alchemyapi.io/v2/...` |
| Native token | INJ (for gas) |
| Payment token | WUSDT (EIP-3009 wrapped USDT) |

## Use Cases

- **Pay-per-query market data APIs** — charge 0.001 USDT per price/candle request
- **AI inference endpoints** — monetize Claude or other LLM calls with micropayments
- **Premium signal feeds** — trading signals, whale alerts, liquidation data
- **Agent-to-agent payments** — one AI agent pays another for data or computation

## Example: AI Agent Paying for Market Intelligence

```ts
// Agent fetches premium Injective analytics, auto-pays per request
const analytics = await x402Client.fetch(
  'https://analytics.injective.network/api/whale-flows'
)
// Payment happens transparently — no user interaction needed
```

## Notes

- The facilitator wallet needs INJ for gas to settle payments on-chain.
- EIP-3009 authorizations include a deadline — default 60s. Size accordingly.
- The x402 package is under active development. Check `/Users/ck/dev/x402/` for latest.
- For testnet, use `INJECTIVE_TESTNET_CAIP2` and deploy WUSDT to testnet separately.
