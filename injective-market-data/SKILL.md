---
name: injective-market-data
description: Access real-time market data for Injective perpetual futures markets. Query oracle prices, list all active markets with metadata (tick size, min notional, max leverage), and retrieve current spread and funding information. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective Market Data Skill

## Overview

Query live market data from Injective's on-chain perpetuals exchange. All data is pulled from the Injective Indexer (gRPC) and is real-time.

## Available Tools

### market_list
Lists all active perpetual futures markets with full metadata.

```
market_list
```

Returns per market:
- `symbol` — e.g. BTC, ETH, INJ
- `marketId` — 0x... hex ID used on-chain
- `oraclePrice` — current oracle mark price (USDT)
- `minQuantityTickSize` — minimum order size
- `minPriceTickSize` — minimum price increment
- `initialMarginRatio` — minimum margin (1/maxLeverage)
- `maintenanceMarginRatio`
- `makerFeeRate` / `takerFeeRate`

### market_price
Get the current oracle price for a single market.

```
market_price
  symbol: BTC    ← or ETH, INJ, SOL, ATOM, etc.
```

Returns: `{ symbol, price, marketId }`

## Common Workflows

### "What markets are available?"
```
market_list → filter/display by symbol
```

### "What's the current BTC price?"
```
market_price BTC
```

### "What's the max leverage for ETH?"
```
market_list → find ETH → compute 1 / initialMarginRatio
```
(e.g. initialMarginRatio 0.05 → 20x max leverage)

### "Is the ETH market liquid enough for a $10,000 position?"
```
market_list → check ETH minQuantityTickSize and current oracle price
```
Injective uses an on-chain order book. For large orders, use limit orders or split into multiple market orders to reduce slippage.

## Market Symbol Reference

Common active markets: BTC, ETH, INJ, SOL, ATOM, BNB, LINK, AVAX, ARB, OP, DOGE, PEPE, WIF, TIA, BONK, PYTH, SEI, SUI, APT, NEAR

Use `market_list` for the complete current set — new markets are added by Injective governance.

## Notes

- Prices are in USDT with 6 decimal places internally; returned as human-readable floats.
- Oracle prices are aggregated from Band Protocol and Pyth Network feeds.
- Funding rates are not yet exposed via MCP tools — check Helix UI for funding.
- Market data is cached in-process for 30 seconds to reduce latency on repeated calls.
