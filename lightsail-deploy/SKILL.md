---
name: lightsail-deploy
description: Deploy a Node.js project to an AWS Lightsail, OVH, or other Linux server via SSH, rsync, PM2, nginx, and trusted HTTPS. Handles first-time production launches, mandatory health.ckh.dev fleet registration, Let's Encrypt certificates for domains or static IP addresses, automated renewal, firewall verification, and public health checks. Use when the user says "deploy", "push to server", "update the server", "ship it", or asks to launch a new product on a server.
license: MIT
metadata:
  author: ck
  version: "1.2.0"
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
   - `domain` — public domain, or the static public IP when no domain is assigned
   - `nginx_site` — path to the nginx config (`/etc/nginx/sites-available/<domain-or-app>`)
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

## Mandatory health registration

Before declaring any deployment complete, invoke the `health-ckh-dev` skill for
the target host. This gate applies to first deployments and newly discovered
servers across Lightsail, OVH, and other Linux providers.

1. Check whether the host already has a registered collector in
   `health.ckh.dev`. If it does, register the new PM2 process in its durable
   expected inventory. If it does not, install and verify a loopback-bound
   health collector, its restricted nginx route, and a unique token.
2. Add the exact PM2 processes whose absence should fail fleet health. Do not
   guess names or mark a stopped process ignored without an explicit reason.
3. Verify the target collector and service routes from Tokyo, then verify the
   authenticated dashboard catalog and overall route.
4. Only after those checks pass may the deployment be reported as complete.

If SSH access, the collector route, or the firewall path is unavailable, report
that precise blocker and leave the deployment incomplete. Do not add a
placeholder server to the dashboard, claim it is monitored, or skip the health
gate because the host is OVH or because the application itself deployed
successfully.

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
If a health endpoint exists, hit it via the public HTTPS URL, not just localhost on the server:
```bash
curl -s -o /dev/null -w "%{http_code}\n" https://<domain>/health
# or
curl -s -o /dev/null -w "%{http_code}\n" https://<static_server_ip>/health
```

### 6. Tail logs if anything is off
```bash
ssh -i <ssh_key> <host> "pm2 logs <pm2_process> --lines 30 --nostream"
```

## HTTPS is part of done

Every new public product must ship with trusted HTTPS during its initial deployment. Do not leave an authenticated dashboard, login form, API credential, wallet view, or other product endpoint on plain HTTP because a domain is not ready.

Choose the public identity in this order:

1. Use the product's domain when its DNS record points to the server.
2. Otherwise, use the server's Lightsail static public IP and obtain a Let's Encrypt IP address certificate.

Before certificate issuance, confirm that the Lightsail networking firewall and any host firewall allow public TCP 80 and 443. Port 80 must remain available for the HTTP-01 challenge. Port 443 serves the product. If the cloud firewall cannot be changed with the available AWS access, report that exact blocker and do not claim that the public HTTPS deployment is complete.

## Nginx setup (first deploy only)

For a new project, configure nginx as a reverse proxy. The site config typically includes:
- `proxy_pass http://localhost:<port>`
- WebSocket upgrade headers (`Upgrade`, `Connection`) if the app uses websockets
- Standard proxy headers (`X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`)
- `proxy_read_timeout 86400` for long-lived connections

```bash
ssh -i <ssh_key> <host> "sudo vim /etc/nginx/sites-available/<domain-or-app>"
ssh -i <ssh_key> <host> "sudo ln -sf /etc/nginx/sites-available/<domain-or-app> /etc/nginx/sites-enabled/"
ssh -i <ssh_key> <host> "sudo nginx -t && sudo systemctl reload nginx"
```

## Let's Encrypt for a domain

Once the DNS A-record for `<domain>` resolves to the server:
```bash
ssh -i <ssh_key> <host> "sudo certbot --nginx -d <domain> --non-interactive --agree-tos --email <admin_email>"
```
Do not run domain validation before DNS points to the server. Confirm Certbot's renewal timer is enabled, run a dry-run renewal, and verify the HTTPS URL from outside the server.

## Let's Encrypt for a static IP address

Let's Encrypt supports publicly trusted IPv4 and IPv6 certificates. IP certificates require the `shortlived` profile and are valid for 160 hours, so reliable automated renewal is mandatory.

1. Confirm that the address is a Lightsail static IP. Do not bind a certificate to an ephemeral address.
2. Install Certbot 5.4 or newer from a current supported package source and confirm with `certbot --version`.
3. Create a dedicated webroot, such as `/var/www/<app>-acme`, and configure the port-80 nginx vhost to serve `/.well-known/acme-challenge/` from it. Redirect every other HTTP request to `https://<static_server_ip>$request_uri`.
4. Test issuance against staging first, then obtain the trusted production certificate without `--staging`:

```bash
sudo certbot certonly \
  --preferred-profile shortlived \
  --webroot \
  --webroot-path /var/www/<app>-acme \
  --ip-address <static_server_ip> \
  --non-interactive --agree-tos --email <admin_email>
```

Certbot does not install IP certificates into nginx. Configure the port-443 vhost manually with:

```nginx
ssl_certificate /etc/letsencrypt/live/<static_server_ip>/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/<static_server_ip>/privkey.pem;
```

Install an executable Certbot deploy hook under `/etc/letsencrypt/renewal-hooks/deploy/` that runs `systemctl reload nginx`. Then verify both the renewal scheduler and the hook:

```bash
systemctl list-timers --all | grep -E 'certbot|snap.certbot.renew'
sudo certbot renew --dry-run --run-deploy-hooks
```

Because an IP certificate has a roughly six-day lifetime, treat a failed renewal timer or deploy hook as a production incident.

## Public TLS verification

Finish every new product deployment with public checks from outside the server:

```bash
curl -fsSI http://<domain-or-static-ip>/
curl -fsSI https://<domain-or-static-ip>/
curl -fsS https://<domain-or-static-ip>/health
```

Confirm HTTP redirects to HTTPS, the certificate is trusted for the exact domain or IP, the application response is correct, and nginx is proxying with `X-Forwarded-Proto`. Record the certificate name, certificate paths, ACME webroot, renewal timer, deploy hook, ports 80 and 443, and verification commands in the private `DEPLOYMENT.md`.

## Notes

- SSH user is always `ubuntu@` on Lightsail Ubuntu instances.
- Never upload `.env` — it should already exist on the server. If you need to seed one, copy it separately with `scp` and `chmod 600` it.
- Fresh-server Node.js install: `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs && sudo npm install -g pm2 tsx`
- For TypeScript projects without a build step: `pm2 start "npx tsx src/index.ts" --name <pm2_process> --cwd <app_dir>`
- Always verify via the public HTTPS URL last, after the PM2 restart and nginx reload, not just localhost on the server.
