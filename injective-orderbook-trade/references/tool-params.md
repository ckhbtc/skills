# Injective Trade — MCP Tool Parameter Reference

## trade_open / trade_close

| Param | Type | Required | Notes |
|---|---|---|---|
| address | string | ✓ | inj1... bech32 address |
| password | string | ✓ | Keystore password |
| market | string | ✓ | Symbol: BTC, ETH, INJ, SOL, ATOM, etc. |
| side | long\|short | ✓ (open only) | Direction |
| amount | number | ✓ | USDT notional |
| leverage | number | ✓ (open only) | 1–20 |
| slippage | number | — | Fraction: 0.01 = 1%. Default: open=0.01, close=0.05 |

## trade_open_eip712 / trade_close_eip712

Same as above minus `password`. Signs via EIP-712 typed data (MetaMask-compatible). The address must be unlockable with the stored EVM key.

## trade_limit_open

| Param | Type | Required | Notes |
|---|---|---|---|
| address | string | ✓ | inj1... |
| password | string | ✓ | |
| market | string | ✓ | Symbol |
| side | buy\|sell | ✓ | buy = bid (long), sell = ask (short) |
| price | number | ✓ | Limit price in USDT |
| amount | number | ✓ | USDT notional |
| leverage | number | ✓ | 1–20 |

## trade_limit_orders

| Param | Type | Required | Notes |
|---|---|---|---|
| address | string | ✓ | inj1... |
| market | string | — | Filter by market symbol |
| subaccountId | string | — | Override subaccount (default: index 0) |

## trade_limit_close

| Param | Type | Required | Notes |
|---|---|---|---|
| address | string | ✓ | inj1... |
| password | string | ✓ | |
| market | string | ✓ | Symbol |
| orderHash | string | ✓ | 0x... hash from trade_limit_orders |

## trade_limit_states

| Param | Type | Required | Notes |
|---|---|---|---|
| orderHashes | string[] | ✓ | Array of 0x... hashes |

## account_positions (read — use before closing)

| Param | Type | Required | Notes |
|---|---|---|---|
| address | string | ✓ | inj1... |
| market | string | — | Filter by symbol |

Returns: market, direction, quantity, entryPrice, markPrice, unrealizedPnl, margin.
