---
name: injective-slack-alert
description: Build a Slack alert daemon that polls on-chain or off-chain state on Injective and posts a message when something changes. Use when the user wants a new alert bot — health monitor, security watchdog, OI surge detector, contract change detector, balance-low alerter, etc. — to live alongside their existing alerts (ins-alerts, qlps-alerts, liquidation-chain). Produces a single-file Node.js + Express + node-cron + sqlite + Slack WebClient service deployable via PM2.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective Slack Alert Skill

## Overview

A consistent recipe for building Slack-alerting daemons that watch some piece of
Injective state (LCD queries, indexer endpoints, contract config, etc.) and
notify a channel when it changes or breaches a threshold.

The recipe matches the existing fleet of alert services (ins-alerts,
qlps-alerts, olp-health, liquidation-chain). Following it means new alerts feel
like part of the family — same env-var names, same dry-run flag, same
deployment shape, same log format, same dedup pattern.

## When to use

Trigger this skill when the user asks for any of:

- "Make a Slack alert that watches X"
- "Build me a monitor for X"
- "I want to be alerted if Y changes / drops below Z"
- "Set up a watchdog for the contract"
- "Add this to my alert bots" / "make another alert like ins-alerts"

If the user already has the project scaffolded and just wants to add a new
check, skip the scaffold step and just add the new check function.

## Architecture (use this exact shape)

```
my-alert/
├── monitor.js              ← single-file entry (Express + cron + checks)
├── package.json
├── ecosystem.config.js     ← PM2
├── data/                   ← gitignored, sqlite lives here
│   └── state.db
├── .env.example            ← documented sample
├── .env                    ← gitignored
├── .gitignore
├── README.md
└── DEPLOYMENT.md           ← gitignored, server-specific
```

**Stack — do not deviate without reason:**

- Node.js 18+ (CommonJS, `require()`)
- `express` for the HTTP control surface
- `node-cron` for scheduled checks (use `setInterval` only for sub-minute polls)
- `sqlite3` for state + dedup history
- `@slack/web-api` (`WebClient`) for Block Kit / mrkdwn messages
- `axios` for HTTP, `dotenv` for env loading

## Conventions

### Environment variables (always)

```env
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXXXXXX        # the bot user must be in this channel
SLACK_MENTION_USER_IDS=             # comma-separated, optional
PORT=1XXXX                          # pick from the unused range — see below
DRY_RUN=false                       # true = log instead of post to Slack
INJECTIVE_LCD=https://sentry.lcd.injective.network
```

Plus whatever check-specific config the bot needs (`POLL_SECONDS`,
`THRESHOLD_PCT`, `WATCHED_CONTRACTS`, etc.).

### Port allocation

Each alert service binds a distinct port for its `/health` endpoint. Existing
allocations (kept here so new bots don't collide):

| Service | Port |
|---|---|
| qlps-alerts | 12000 |
| ins-alerts | 14000 |
| liquidation-chain | 16000 |
| olp-health | 18000 |

Pick a fresh port for new services. Suggested range: 12000–20000, in 500-step
increments to leave headroom. Document the new port in DEPLOYMENT.md.

### Slack channel

Always use a **dedicated channel per alert family**. Don't pile every bot's
output into one firehose. Hardcode the channel ID via `SLACK_CHANNEL_ID` env
var — never paste channel IDs into source.

For security-grade alerts (admin changes, key rotations, fund movement),
mention specific user IDs via `SLACK_MENTION_USER_IDS` instead of `<!here>`.
For health/info alerts, no mentions.

### Log format

Every line gets a UTC timestamp prefix. Use this helper verbatim:

```javascript
function ts() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `[${now.getUTCFullYear()}-${pad(now.getUTCMonth() + 1)}-${pad(now.getUTCDate())} ${pad(now.getUTCHours())}:${pad(now.getUTCMinutes())}:${pad(now.getUTCSeconds())} UTC]`;
}
function log(msg) { console.log(`${ts()} ${msg}`); }
function logErr(msg, err) { console.error(`${ts()} ${msg}`, err && err.message ? err.message : err || ''); }
```

Use emojis in log lines: ✅ success, ❌ error, 🚨 critical alert, ⚠️ warn,
🔄 cycle, 📡 fetch, 💾 db write, 👋 shutdown.

### Dry-run mode

`DRY_RUN=true` must short-circuit all Slack calls and log what *would* have
been posted. Run via `npm run dev`. Required for safe local development.

## The monitor.js skeleton

Drop this in and fill the TODOs. It has the boot, dotenv, sqlite, Slack
WebClient, cron loop, dry-run, and `/health` endpoint already wired.

```javascript
require('dotenv').config();
const express = require('express');
const axios = require('axios');
const cron = require('node-cron');
const path = require('path');
const fs = require('fs');
const sqlite3 = require('sqlite3').verbose();
const { WebClient } = require('@slack/web-api');

// ---- config ----
const PORT = parseInt(process.env.PORT || '1XXXX', 10);  // TODO: pick a port
const POLL_SECONDS = parseInt(process.env.POLL_SECONDS || '300', 10);
const LCD = (process.env.INJECTIVE_LCD || 'https://sentry.lcd.injective.network').replace(/\/+$/, '');
const DRY_RUN = String(process.env.DRY_RUN || 'false').toLowerCase() === 'true';
const SLACK_BOT_TOKEN = process.env.SLACK_BOT_TOKEN;
const SLACK_CHANNEL_ID = process.env.SLACK_CHANNEL_ID;
const SLACK_MENTION_USER_IDS = (process.env.SLACK_MENTION_USER_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
const slack = SLACK_BOT_TOKEN ? new WebClient(SLACK_BOT_TOKEN) : null;

// ---- logging ----
function ts() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `[${now.getUTCFullYear()}-${pad(now.getUTCMonth()+1)}-${pad(now.getUTCDate())} ${pad(now.getUTCHours())}:${pad(now.getUTCMinutes())}:${pad(now.getUTCSeconds())} UTC]`;
}
const log = (m) => console.log(`${ts()} ${m}`);
const logErr = (m, e) => console.error(`${ts()} ${m}`, e?.message || e || '');

// ---- db ----
const DATA_DIR = path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
const db = new sqlite3.Database(path.join(DATA_DIR, 'state.db'));
db.serialize(() => {
  // TODO: define your tables. Common shape:
  //   - one table for snapshots/observations (history)
  //   - one table for change_events / alert_log (dedup + audit)
  db.run(`CREATE TABLE IF NOT EXISTS alert_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts DATETIME DEFAULT CURRENT_TIMESTAMP,
    key TEXT NOT NULL,
    severity TEXT NOT NULL,
    message TEXT NOT NULL
  )`);
});

// ---- check ----
async function runCheck() {
  // TODO: fetch the thing you care about
  // TODO: compare to last known state in db
  // TODO: if breached/changed, call postAlert()
}

// ---- slack ----
async function postAlert({ key, severity, text }) {
  const isLoud = severity === 'CRITICAL' || severity === 'HIGH';
  const mention = isLoud && SLACK_MENTION_USER_IDS.length
    ? SLACK_MENTION_USER_IDS.map(u => `<@${u}>`).join(' ') + ' '
    : isLoud ? '<!here> ' : '';
  const fullText = `${mention}${text}`;

  if (DRY_RUN || !slack || !SLACK_CHANNEL_ID) {
    log(`[DRY_RUN] would post: ${fullText}`);
    return;
  }
  try {
    await slack.chat.postMessage({
      channel: SLACK_CHANNEL_ID,
      text: fullText,
      mrkdwn: true,
      link_names: true,
      unfurl_links: false,
      unfurl_media: false,
    });
    db.run(`INSERT INTO alert_log (key, severity, message) VALUES (?,?,?)`, [key, severity, text]);
    log(`✅ posted Slack alert: ${key} (${severity})`);
  } catch (e) {
    logErr('❌ slack post failed:', e);
  }
}

// ---- express ----
const app = express();
app.get('/', (req, res) => res.json({
  service: 'TODO-name', dry_run: DRY_RUN, poll_seconds: POLL_SECONDS,
  slack_configured: Boolean(slack && SLACK_CHANNEL_ID),
}));
app.get('/health', (req, res) => res.json({ ok: true, ts: new Date().toISOString() }));
app.get('/check-now', async (req, res) => {
  try { await runCheck(); res.json({ ok: true }); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// ---- boot ----
const isOneShot = process.argv.includes('--once');
if (isOneShot) {
  runCheck().then(() => process.exit(0)).catch(e => { logErr('fatal:', e); process.exit(1); });
} else {
  app.listen(PORT, () => {
    log(`🟢 listening on :${PORT} (DRY_RUN=${DRY_RUN}, POLL_SECONDS=${POLL_SECONDS})`);
    runCheck().catch(e => logErr('initial check failed:', e));
    cron.schedule(`*/${Math.max(1, Math.round(POLL_SECONDS / 60))} * * * *`, () => {
      runCheck().catch(e => logErr('cycle failed:', e));
    });
    if (POLL_SECONDS < 60) {
      setInterval(() => runCheck().catch(e => logErr('cycle failed:', e)), POLL_SECONDS * 1000);
    }
  });
}
process.on('SIGINT', () => { log('👋 SIGINT'); db.close(() => process.exit(0)); });
process.on('uncaughtException', (e) => logErr('uncaughtException:', e));
process.on('unhandledRejection', (e) => logErr('unhandledRejection:', e));
```

## package.json

```json
{
  "name": "TODO-alert-name",
  "version": "1.0.0",
  "main": "monitor.js",
  "scripts": {
    "start": "node monitor.js",
    "dev": "DRY_RUN=true node monitor.js",
    "check": "node monitor.js --once"
  },
  "dependencies": {
    "@slack/web-api": "^6.8.1",
    "axios": "^1.6.0",
    "dotenv": "^17.3.1",
    "express": "^4.18.2",
    "node-cron": "^3.0.3",
    "sqlite3": "^5.1.6"
  },
  "engines": { "node": ">=18.0.0" }
}
```

## .env.example

```env
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXXXXXX
SLACK_MENTION_USER_IDS=
INJECTIVE_LCD=https://sentry.lcd.injective.network
PORT=1XXXX
POLL_SECONDS=60
DRY_RUN=false
```

## .gitignore (always)

```
node_modules/
.env
data/
*.db
*.db-journal
.DS_Store
CLAUDE.md
DEPLOYMENT.md
*.log
```

## ecosystem.config.js

```javascript
module.exports = {
  apps: [{
    name: 'TODO-alert-name',
    script: 'monitor.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '256M',
    env: { NODE_ENV: 'production' },
    error_file: 'logs/err.log',
    out_file: 'logs/out.log',
    time: true,
  }],
};
```

## Workflow when scaffolding a new alert

1. **Confirm scope with the user.** What's being watched? What threshold/rule
   triggers an alert? What channel? Severity rules?
2. **Pick a port** (see allocation table above) and a unique service name.
3. `mkdir <project> && cd <project>` — usually under `~/dev/`.
4. Drop in the files above (monitor.js, package.json, .env.example, .gitignore,
   ecosystem.config.js).
5. `cp .env.example .env` and fill in placeholder values. Tell the user to
   replace the real bot token / channel ID / etc. in `.env` before running.
6. Implement `runCheck()` against the real data source. Keep the function
   small — fetch, diff, alert.
7. Boot in dry-run: `npm install && npm run dev`. Verify the cycle log line
   prints and `/health` responds.
8. Write README.md (what it watches, endpoints, run modes).
9. Write DEPLOYMENT.md (gitignored — server target, app dir, PM2 process name,
   port, deploy command sequence). Use the `lightsail-deploy` skill for the
   actual deploy.

## State / dedup patterns

Pick the right one for the job.

| Pattern | Use when | Storage |
|---|---|---|
| **Per-key cooldown** (e.g. 30 min between repeats) | Health metrics that flap | sqlite or in-memory `Map<key, lastAlertTime>` |
| **Diff-on-change** (only alert when state differs from last snapshot) | Watching config / settings | sqlite snapshot table |
| **Threshold breach** (alert on cross, then again on un-cross / "resolved") | Up/down monitors | in-memory flag + sqlite |

For long-term persistence + audit trail, prefer sqlite (used in ins-alerts,
qlps-alerts, this skill's skeleton). For fast ephemeral stuff (health checks,
liquidation watcher), an in-memory Map is fine — `liquidation-chain` does this.

## Slack message style

Keep it tight. Pattern:

```
🚨 *Title — what changed* (SEVERITY)
<@U...> Subject: `value`

• field1: `old` → `new`
• field2: `old` → `new`

🔍 https://explorer.injective.network/...
_Detected at 2026-04-26T18:52:08Z_
```

Use `mrkdwn: true` and bold headers with `*...*`. Use code spans for addresses,
hashes, denoms. For richer alerts (categorized lists, multiple sections), use
Block Kit via `slack.chat.postMessage({ blocks: [...] })` — see `ins-alerts`
weekly digest for an example.

## Security pitfalls — DO NOT

- ❌ Hardcode server IPs, SSH key paths, bot tokens, channel IDs, or user IDs
  in source files. All of those are env vars.
- ❌ Commit the `.env` file. Always `.gitignore` it.
- ❌ Commit `DEPLOYMENT.md`. Server topology stays out of public repos.
- ❌ Log secrets. If you're tempted to `console.log(process.env.SLACK_BOT_TOKEN)`
  for debugging, log `Boolean(token)` instead.
- ❌ Create the bot without DRY_RUN gating. The first run from a dev machine
  must be safe by default.

## Companion skill

Use `lightsail-deploy` once the alert is built, to push it to the server.
