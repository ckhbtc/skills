# Skills for Claude Code

Personal Claude Code skills — Injective-focused trading + ops tools, plus a few general-purpose helpers (blog writing, data analysis, deployment).

## Skills

| Skill | Description |
|---|---|
| [`injective-market-data`](./injective-market-data/) | Real-time perpetuals market prices and metadata |
| [`injective-account`](./injective-account/) | Wallet balances, subaccount balances, open positions + P&L |
| [`injective-token`](./injective-token/) | Token metadata, transfers, subaccount deposit/withdraw |
| [`injective-trade`](./injective-trade/) | Market + limit order trading (Cosmos & EIP-712 signing) |
| [`injective-positions`](./injective-positions/) | Query, close, flatten derivative positions across many wallets |
| [`injective-bridge`](./injective-bridge/) | Cross-chain bridging via deBridge DLN + Peggy |
| [`injective-autosign`](./injective-autosign/) | AuthZ delegation for session-based auto-trading |
| [`injective-authz-ops`](./injective-authz-ops/) | Mass-grant / manage AuthZ permissions |
| [`injective-funding`](./injective-funding/) | Mass-fund wallets (INJ/USDT/USDC), public faucet pattern |
| [`injective-wallet-ops`](./injective-wallet-ops/) | Mass create/derive wallets, address conversion |
| [`injective-staking`](./injective-staking/) | Staking delegations, rewards, validator queries |
| [`injective-chain-analysis`](./injective-chain-analysis/) | Read injective-core Go source, exchange module specs |
| [`injective-x402`](./injective-x402/) | Pay-per-query APIs using x402 protocol on Injective EVM |
| [`injective-slack-alert`](./injective-slack-alert/) | Build a Slack alert daemon (Node.js + Express + cron + sqlite + Slack WebClient) |
| [`lightsail-deploy`](./lightsail-deploy/) | Deploy any Node.js project to AWS Lightsail via SSH + PM2 |
| [`blog-writer`](./blog-writer/) | Write product-announcement blog posts and technical articles |
| [`data-analysis`](./data-analysis/) | Analyze CSV/time-series trading data, generate charts |

## Layout

The canonical files live in this repo. Claude Code loads skills from `~/.claude/skills/`, so each skill is exposed there as a symlink pointing back into this repo:

```
~/.claude/skills/<name>  ->  ../../.agents/skills/<name>
```

That way you edit in one place and Claude Code reads from one place.

## Setup on a new machine

```bash
# 1. Clone
git clone git@github.com:ckhbtc/skills.git ~/.agents/skills

# 2. Symlink every skill into ~/.claude/skills/
~/.agents/skills/bootstrap.sh
```

`bootstrap.sh` is idempotent. Re-run it after `git pull` to pick up any new skills.

## Editing

Edit files in `~/.agents/skills/<name>/`. `~/.claude/skills/<name>/` is just a symlink — touching it edits the same file. After editing:

```bash
cd ~/.agents/skills
git add <name>/
git commit -m "feat(<name>): ..."
git push
```

Then on other machines: `git pull && ./bootstrap.sh` (the bootstrap is needed only if the pull added a new skill directory).

## Prerequisites

- [Injective MCP server](https://github.com/InjectiveLabs/mcp-server) connected to Claude Code (for the `injective-*` skills)
- Claude Code with skill support
