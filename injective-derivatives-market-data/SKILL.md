---
name: injective-derivatives-market-data
description: Access real-time market data for Injective perpetual futures markets — venue-neutral. Query oracle prices, list all active markets with metadata (tick size, min notional, max leverage), and retrieve current spread and funding information. Orderbook and RFQ flows share market IDs, tick sizes, and oracle marks; RFQ uses those values for price protection and validation. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.1.0"
---

# Injective Derivatives Market Data Skill

## Overview

Query live market data from Injective's on-chain perpetuals exchange. All data is pulled from the Injective Indexer (gRPC) and is real-time.

This skill is **venue-neutral**: the same `marketId`, tick sizes, oracle prices, and margin ratios apply to both trading paths on Injective derivatives — the central limit orderbook (`injective-orderbook-trade`) and the RFQ contract (`injective-rfq-trade` / `injective-rfq-quote`). Use this skill from either path.

## Available Tools

### market_list
Lists all active perpetual futures markets with full metadata.

```
market_list
```

Returns per market:
- `symbol` — e.g. BTC, ETH, INJ
- `marketId` — 0x... hex ID used on-chain
- `oraclePrice` — current oracle mark price in the market's quote asset
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

- Prices are returned in the market's quote asset. Many mainnet perps are USDT-quoted; current RFQ testnet examples use USDC margin.
- Oracle prices are aggregated from Band Protocol and Pyth Network feeds.
- Funding rates are not yet exposed via MCP tools — check Helix UI for funding.
- Market data is cached in-process for 30 seconds to reduce latency on repeated calls.

## RFQ note

The RFQ trading path (`injective-rfq-trade`, `injective-rfq-quote`) sits on top of the same derivatives markets, so everything this skill returns applies there too. A few RFQ-specific reminders when consuming `market_list` output for an RFQ flow:

- **`min_price_tick_size`** — quote prices must be quantized to this tick before signing. Decimal strings are hashed as `keccak256(utf8(s))` in the EIP-712 v2 digest, so the wire string must be canonical (no trailing zeros, no `.0` on whole-integer ticks). For BTC perp at tick `1`, that means `"76462"` — not `"76462.0"`. See `injective-rfq-quote` for the `to_canonical(x, tick)` helper.
- **`worst_price`** — RFQ requests carry taker price protection. Current testnet validation rejects requests outside the configured mark-price band: long <= mark x 1.10, short >= mark x 0.90 by default. Pull the mark from `market_price` and set `worst_price` accordingly.
- **`maker_fee_rate` / `taker_fee_rate`** — these are the orderbook fees. RFQ settles via `MsgPrivilegedExecuteContract`, so fees are handled by the RFQ contract config (typically zero / sponsor-paid during the testnet phase).
- **`marketId`** — same hex on both venues. Pass through unchanged when bridging an orderbook market into an RFQ flow.

RFQ is currently testnet-only. When targeting RFQ testnet endpoints, use market IDs and tick sizes from the matching Injective testnet environment.
