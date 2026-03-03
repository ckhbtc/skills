# Injective Skills for Claude Code

Claude Code skills that give AI agents full Injective trading capabilities via the [Injective MCP server](https://github.com/InjectiveLabs/mcp-server).

## Skills

| Skill | Description |
|---|---|
| [`injective-market-data`](./injective-market-data/) | Real-time perpetuals market prices and metadata |
| [`injective-account`](./injective-account/) | Wallet balances, subaccount balances, open positions + P&L |
| [`injective-token`](./injective-token/) | Token metadata, transfers, subaccount deposit/withdraw |
| [`injective-trade`](./injective-trade/) | Market + limit order trading (Cosmos & EIP-712 signing) |
| [`injective-bridge`](./injective-bridge/) | Cross-chain bridging via deBridge DLN + Peggy |
| [`injective-autosign`](./injective-autosign/) | AuthZ delegation for session-based auto-trading |
| [`injective-x402`](./injective-x402/) | Pay-per-query APIs using x402 protocol on Injective EVM |

## Prerequisites

1. [Injective MCP server](https://github.com/InjectiveLabs/mcp-server) connected to Claude Desktop or Claude Code
2. Claude Code with skill support

## Install

```bash
# Install all skills
for skill in injective-market-data injective-account injective-token injective-trade injective-bridge injective-autosign injective-x402; do
  cp -r $skill ~/.claude/skills/
done
```

Or install individually:
```bash
cp -r injective-trade ~/.claude/skills/
```

## Usage

Once installed, Claude will use these skills automatically when you make Injective-related requests:

```
> What's the current BTC price on Injective?
> Show my balances for inj1...
> Open a $100 long on ETH with 5x leverage
> Bridge 50 USDC from Arbitrum to Injective
> Set up AutoSign for the next 24 hours
```
