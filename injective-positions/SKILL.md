---
name: injective-positions
description: Query, close, and flatten derivative positions on Injective. Mass close all positions across wallets, flatten positions via RFQ trades using a garbage collector pattern, and query position details (quantity, margin, entry price, PnL). Supports mass operations across many wallets.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective Position Management Skill

## Overview

Query, close, and rebalance derivative positions on Injective. Supports mass operations across many wallets. Based on an Injective RFQ test framework.

## Reference Code

- **Query positions**: `src/rfq_test/clients/chain.py` → `get_derivative_position()`
- **Mass close**: `scripts/close_all_positions.py`
- **Flatten via RFQ**: `scripts/flatten_mm_positions.py`, `src/rfq_test/utils/flatten.py`
- **Price fetching**: `src/rfq_test/utils/price.py` → `PriceFetcher`

## Query Positions

### Via LCD REST API
```python
# Single position query
GET /injective/exchange/v2/positions/{subaccount_id}/{market_id}

# Returns: quantity, is_long, margin, entry_price (or empty if no position)
```

### Via ChainClient
```python
async def get_derivative_position(self, address, market_id, subaccount_nonce=0):
    subaccount_id = get_subaccount_id(address, nonce=subaccount_nonce)
    url = f"{self.lcd}/injective/exchange/v2/positions/{subaccount_id}/{market_id}"
    resp = await self.http.get(url)
    data = resp.json()
    state = data.get("state", {})
    if not state.get("quantity"):
        return None
    return {
        "quantity": Decimal(state["quantity"]),
        "is_long": state.get("isLong", False),
        "margin": Decimal(state.get("margin", "0")),
        "entry_price": Decimal(state.get("entryPrice", "0")),
    }
```

### Multi-nonce query (debug)
Check nonces 0, 1, 2 for positions that might be on different subaccounts:
```python
for nonce in [0, 1, 2]:
    pos = await chain_client.get_derivative_position(address, market_id, nonce)
    if pos: print(f"Nonce {nonce}: {pos}")
```

## Mass Close Positions

### Market Order Close (direct on-chain)
From `close_all_positions.py`:
```python
async def close_position_for_wallet(private_key, market_id, network):
    # 1. Query current position
    position = await chain_client.get_derivative_position(address, market_id)
    if not position:
        return  # No position to close

    # 2. Get mark price
    mark_price = await price_fetcher.get_mark_price(market_id)

    # 3. Create closing market order
    # Long -> SELL, Short -> BUY
    # Price = mark_price * 0.9 (long) or mark_price * 1.1 (short)
    side = "sell" if position["is_long"] else "buy"
    worst_price = mark_price * (Decimal("0.9") if position["is_long"] else Decimal("1.1"))

    msg = composer.msg_create_derivative_market_order(
        sender=address,
        market_id=market_id,
        subaccount_id=subaccount_id,
        fee_recipient=address,
        price=float(worst_price),
        quantity=float(position["quantity"]),
        margin=0,  # margin=0 for closing orders
        order_type="sell" if position["is_long"] else "buy",
        is_reduce_only=True,
    )
```

### Flatten via RFQ (Garbage Collector Pattern)
More sophisticated: uses actual RFQ trades to net out positions.

**Architecture**:
- **GC wallet** = MM seed index 99 (absorbs everything)
- **Absorber MM** = MM seed index 98 (intermediary for retail)
- Phase 1: Each retail wallet closes into absorber MM via RFQ
- Phase 2: GC absorbs all MM positions via RFQ

```bash
# Dry run (just query)
python scripts/flatten_mm_positions.py --env testnet --dry-run

# Flatten specific MM indices
python scripts/flatten_mm_positions.py --env testnet --mm-indices 0,1,2,3

# Flatten retail through absorber
python scripts/flatten_mm_positions.py --env testnet --retail-indices 0-9 --retail-absorber-mm 98
```

## Price Fetching
```python
class PriceFetcher:
    """Fetches mark prices from Injective LCD. 60s TTL cache."""
    async def get_mark_price(self, market_id) -> Decimal:
        # Tries: v2 derivative market -> oracle price -> last known -> config fallback
```

## Key Facts
- `margin=0` for closing/reduce-only orders
- Slippage: 10% from mark price is safe for mass closes
- `is_reduce_only=True` prevents accidentally opening a new position
- Subaccount nonce 0 is default; testnet demo scripts sometimes use nonce 1
- `MIN_FLATTEN_QUANTITY = 0.01` -- skip dust positions

## Dependencies
- `injective-py>=1.12.0`
- `httpx>=0.27` (for LCD queries)
- Python >= 3.11
