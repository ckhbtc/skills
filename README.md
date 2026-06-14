# Skills for Claude Code

Personal Claude Code skills — Injective-focused trading + ops tools, plus a few general-purpose helpers (blog writing, data analysis, deployment).

## Skills

| Skill | Description |
|---|---|
| [`injective-derivatives-market-data`](./injective-derivatives-market-data/) | Real-time perpetuals market prices and metadata (orderbook + RFQ) |
| [`injective-frontend-wallet`](./injective-frontend-wallet/) | Build, review, debug browser frontends signing Injective txs (Keplr/Leap/MetaMask, CosmJS, ethsecp256k1, EthAccount) |
| [`injective-account`](./injective-account/) | Wallet balances, subaccount balances, open positions + P&L |
| [`injective-token`](./injective-token/) | Token metadata, transfers, subaccount deposit/withdraw |
| [`injective-orderbook-trade`](./injective-orderbook-trade/) | Market + limit order trading on the central orderbook (Cosmos & EIP-712 signing) |
| [`injective-rfq-trade`](./injective-rfq-trade/) | Take a position via RFQ — request quotes, pick best, accept on-chain (testnet only) |
| [`injective-rfq-quote`](./injective-rfq-quote/) | Provide liquidity as an RFQ market maker — receive requests, sign quotes (EIP-712 v2), stream back (testnet only) |
| [`injective-rfq-conditional-order`](./injective-rfq-conditional-order/) | Pre-sign TP/SL signed-intents that fire on mark-price triggers (testnet only) |
| [`injective-rfq-autosign`](./injective-rfq-autosign/) | AuthZ grants for the RFQ contract (`MsgSend` + `MsgPrivilegedExecuteContract`) — required for both MM and Retail |
| [`injective-rfq-mm-onboarding`](./injective-rfq-mm-onboarding/) | One-shot MM onboarding — whitelist, grants, balances, smoke test (testnet only) |
| [`injective-positions`](./injective-positions/) | Query, close, flatten derivative positions across many wallets |
| [`injective-bridge`](./injective-bridge/) | Cross-chain bridging via deBridge DLN + Peggy |
| [`injective-orderbook-autosign`](./injective-orderbook-autosign/) | AuthZ delegation for session-based auto-trading on the orderbook |
| [`injective-authz-ops`](./injective-authz-ops/) | Mass-grant / manage AuthZ permissions |
| [`injective-funding`](./injective-funding/) | Mass-fund wallets (INJ/USDT/USDC), public faucet pattern |
| [`injective-wallet-ops`](./injective-wallet-ops/) | Mass create/derive wallets, address conversion |
| [`injective-staking`](./injective-staking/) | Staking delegations, rewards, validator queries |
| [`injective-chain-analysis`](./injective-chain-analysis/) | Read injective-core Go source, exchange module specs |
| [`injective-x402`](./injective-x402/) | Pay-per-query APIs using x402 protocol on Injective EVM |
| [`lightsail-deploy`](./lightsail-deploy/) | Deploy any Node.js project to AWS Lightsail via SSH + PM2 |
| [`blog-writer`](./blog-writer/) | Write product-announcement blog posts and technical articles |
| [`data-analysis`](./data-analysis/) | Analyze CSV/time-series trading data, generate charts |

## Layout

The repo lives in `~/dev/skills/` alongside other projects. Skills reach Claude Code through a two-hop symlink chain:

```
~/dev/skills/<name>/                <-- source of truth (this repo)
~/.agents/skills/<name>   ->  ~/dev/skills/<name>             <-- symlink farm (per-skill symlinks)
~/.claude/skills/<name>   ->  ../../.agents/skills/<name>     <-- loaded view (per-skill symlinks)
```

`~/.agents/skills/` is a real directory — a **symlink farm** that can hold entries from multiple source repos at once. `bootstrap.sh` creates both layers in one pass.

### Multi-source note

The farm is shared across three source dirs. Only this repo's skills are managed by `bootstrap.sh`; the others get linked in manually (one-time).

| Source dir | What lives there | How to add |
|---|---|---|
| `~/dev/skills/` | This repo. Personal skills. | `git pull && ./bootstrap.sh` |
| `~/dev/matt-pocock-skills/` | 3rd-party skills (not a repo). | `ln -s ~/dev/matt-pocock-skills/<name> ~/.agents/skills/<name>` then `./bootstrap.sh` |
| `~/dev/agent-skills/skills/` | `InjectiveLabs/agent-skills` (work). | `ln -s ~/dev/agent-skills/skills/<name> ~/.agents/skills/<name>` then `./bootstrap.sh` |

Rule of thumb: the directory name in `~/dev/` tells you which repo you're committing to. Don't cross the streams — personal skills don't go in the org repo, org skills don't get committed here.

## Setup on a new machine

```bash
# 1. Clone to ~/dev/skills (or anywhere — bootstrap auto-detects its location)
git clone git@github.com:ckhbtc/skills.git ~/dev/skills

# 2. Run bootstrap — it creates the farm at ~/.agents/skills/ and links
#    every skill in this repo into both layers.
~/dev/skills/bootstrap.sh
```

`bootstrap.sh` is idempotent. Re-run after `git pull` to pick up new skills, or after manually adding a symlink to the farm from another source.

## Editing

Edit files in `~/dev/skills/<name>/`. `~/.agents/skills/<name>/` and `~/.claude/skills/<name>/` resolve through the chain to the same files, but `git status` only works from `~/dev/skills`. After editing:

```bash
cd ~/dev/skills
git add <name>/
git commit -m "feat(<name>): ..."
git push
```

Then on other machines: `git pull && ./bootstrap.sh` (bootstrap is only needed if the pull added a new skill directory).

## Prerequisites

- [Injective MCP server](https://github.com/InjectiveLabs/mcp-server) connected to Claude Code (for the `injective-*` skills)
- Claude Code with skill support
