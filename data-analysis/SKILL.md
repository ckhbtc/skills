---
name: data-analysis
description: Analyze CSV/time-series trading data, compute statistics (volatility, drawdown, EMA, returns), generate charts, and build financial models. Use when the user shares trading data, asks for quantitative analysis, or needs financial calculations.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Data Analysis Skill

## Overview

Analyze trading data, financial time series, and quantitative metrics. Compute statistics, generate charts, and build models for DeFi/crypto trading strategies.

## Capabilities

### Time Series Analysis
- EMA (Exponential Moving Average) calculations
- Volatility (realized, rolling, annualized)
- Maximum drawdown (rolling windows: 30d, 90d, 12m)
- Returns analysis (daily, weekly, monthly)
- Autocorrelation and mean reversion detection

### Trading Strategy Analysis
- Signal state analysis (NORMAL, LONG, SHORT transitions)
- Win rate and P&L attribution
- Sharpe/Sortino ratios
- Entry/exit timing analysis
- Slippage estimation

### Market Structure
- Volume-to-Open-Interest ratios
- Funding rate analysis
- Liquidation level mapping
- Correlation matrices across assets
- Market depth / orderbook analysis

### Risk Management
- Initial Margin (IM) / Maintenance Margin (MM) optimization
- Leverage tier modeling
- Power-law formulas: `IM = A × MaxLeverage^(-B) × Volatility^(C)`
- VaR (Value at Risk) estimation

## Process

1. **Read the data**: Use Read tool with offset/limit for large files. Check `wc -l` first
2. **Understand structure**: Print head, check column types, identify timestamps
3. **Clean**: Handle missing values, timezone alignment, duplicate rows
4. **Analyze**: Compute requested metrics
5. **Visualize**: Generate charts with matplotlib/plotly if requested
6. **Report**: Summarize findings concisely

## Tools

Prefer Python with:
- `pandas` for dataframes
- `numpy` for numerical computation
- `matplotlib` / `plotly` for charts
- `scipy.stats` for statistical tests

For quick one-off calculations, use Python inline. For reusable analysis, create a script.

## Common Patterns

### Large CSV files (>100K rows)
```python
import pandas as pd
df = pd.read_csv('data.csv', parse_dates=['timestamp'])
print(f"Rows: {len(df)}, Cols: {list(df.columns)}")
print(df.describe())
```

### Margin tier optimization
Given max_leverage and 90d_volatility:
```python
IM = A * max_leverage**(-B) * volatility_90d**(C)
MM = IM * 0.5  # typical ratio
```
Where A, B, C are fitted from exchange data.

### Volume/OI benchmarking
Compare V/OI ratios across DEXes (Hyperliquid, Vertex, Drift, Lighter) to establish realistic targets for new markets.
