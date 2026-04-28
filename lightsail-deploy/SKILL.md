---
name: lightsail-deploy
description: Deploy a Node.js project to an AWS Lightsail server via SSH + rsync + PM2. Handles file upload, dependency install, PM2 restart, nginx verification, and health checks. Use when the user says "deploy", "push to server", "update the server", or "ship it".
license: MIT
metadata:
  author: ck
  version: "1.1.0"
---

# Lightsail Deploy Skill

## Overview

Deploy a project (typically Node.js, but the same shape adapts to anything PM2 can run) to an AWS Lightsail Ubuntu server. The skill is intentionally general — all project-specific and machine-specific values are read from per-project files, never hardcoded here.

## Where the specifics live

This skill never embeds IPs, SSH key paths, app directories, PM2 process names, ports, or domains. Read them from these sources, in order:

1. **`DEPLOYMENT.md` in the project root** — the canonical source for *that* project. It's gitignored (lives next to `CLAUDE.md`, never committed) and should contain:
   - `host` — `ubuntu@<ip>`
   - `ssh_key` — full path to the `.pem` file
   - `app_dir` — `/home/ubuntu/<project>`
   - `pm2_process` — PM2 process name for this app
   - `port` — listen port
   - `domain` — public domain (if any)
   - `nginx_site` — path to the nginx config (`/etc/nginx/sites-available/<domain>`)
   - the quick deploy command sequence
   - log/status checks, SSL renewal, rollback

2. **Global `~/.claude/CLAUDE.md`** — fleet-level server inventory (which IPs exist, which keys, which projects live on which host). Use as a fallback if a project's `DEPLOYMENT.md` is missing, or to reconcile drift between projects.

3. **Ask the user** — only if neither file has the answer.

If `DEPLOYMENT.md` doesn't exist for a project being deployed for the first time, write one as part of the deploy. Add `DEPLOYMENT.md` and `CLAUDE.md` to `.gitignore` if they aren't already.

## Pre-deploy sanity check

Server location info can drift. Before deploying, verify with:
```bash
dig +short <domain>                                      # DNS points where you think
ssh -i <ssh_key> <host> "pm2 list | grep <pm2_process>"  # process exists where you think
```

## Workflow

### 1. Build (if applicable)
```bash
npm run build   # only if the project has a build step
```

### 2. Upload via rsync
```bash
rsync -avz \
  --exclude node_modules --exclude .env --exclude .git --exclude .claude \
  --exclude DEPLOYMENT.md --exclude CLAUDE.md --exclude '*.db' \
  -e "ssh -i <ssh_key>" \
  ./ <host>:<app_dir>/
```
Always exclude `DEPLOYMENT.md` and `CLAUDE.md` — those are local-only.

### 3. Install dependencies (only if `package.json` / lockfile changed)
```bash
ssh -i <ssh_key> <host> "cd <app_dir> && npm install --omit=dev"
```

### 4. Start or restart PM2
```bash
ssh -i <ssh_key> <host> "cd <app_dir> && pm2 restart <pm2_process>"
```
If the process doesn't exist yet:
```bash
ssh -i <ssh_key> <host> "cd <app_dir> && pm2 start <entry_point> --name <pm2_process> && pm2 save"
```
`pm2 save` persists the process list across reboots — only needed once per process.

### 5. Verify
```bash
ssh -i <ssh_key> <host> "pm2 status <pm2_process>"
```
If a health endpoint exists, hit it via the public URL (not just localhost on the server):
```bash
curl -s -o /dev/null -w "%{http_code}\n" https://<domain>/health
# or
curl -s -o /dev/null -w "%{http_code}\n" http://<server_ip>:<port>/
```

### 6. Tail logs if anything is off
```bash
ssh -i <ssh_key> <host> "pm2 logs <pm2_process> --lines 30 --nostream"
```

## Nginx setup (first deploy only)

For a new project, configure nginx as a reverse proxy. The site config typically includes:
- `proxy_pass http://localhost:<port>`
- WebSocket upgrade headers (`Upgrade`, `Connection`) if the app uses websockets
- Standard proxy headers (`X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`)
- `proxy_read_timeout 86400` for long-lived connections

```bash
ssh -i <ssh_key> <host> "sudo vim /etc/nginx/sites-available/<domain>"
ssh -i <ssh_key> <host> "sudo ln -sf /etc/nginx/sites-available/<domain> /etc/nginx/sites-enabled/"
ssh -i <ssh_key> <host> "sudo nginx -t && sudo systemctl reload nginx"
```

## SSL with certbot (first deploy only, requires DNS to be live)

Once the DNS A-record for `<domain>` resolves to the server:
```bash
ssh -i <ssh_key> <host> "sudo certbot --nginx -d <domain> --non-interactive --agree-tos --email <admin_email>"
```
If DNS isn't pointing to the server yet, stop and tell the user — don't run certbot blind. Once it's live, certbot auto-renews via systemd timer; no manual renewal needed.

## Notes

- SSH user is always `ubuntu@` on Lightsail Ubuntu instances.
- Never upload `.env` — it should already exist on the server. If you need to seed one, copy it separately with `scp` and `chmod 600` it.
- Fresh-server Node.js install: `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs && sudo npm install -g pm2 tsx`
- For TypeScript projects without a build step: `pm2 start "npx tsx src/index.ts" --name <pm2_process> --cwd <app_dir>`
- Always verify via the public URL last (after PM2 restart *and* nginx reload), not just localhost on the server.
