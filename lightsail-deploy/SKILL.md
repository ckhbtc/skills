---
name: lightsail-deploy
description: Deploy a Node.js project to an AWS Lightsail server via SSH + SCP + PM2. Handles file upload, PM2 restart, nginx verification, and health checks. Use when the user says "deploy", "push to server", "update the server", or "ship it".
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Lightsail Deploy Skill

## Overview

Deploy any Node.js project to an AWS Lightsail server. Handles the full cycle: upload files, install deps, restart PM2 process, verify health.

## Known Servers

Configure your servers in the project's CLAUDE.md or environment variables. Example format:

| Server | IP | SSH Key | Projects |
|--------|-----|---------|----------|
| Server 1 | `<server-1-ip>` | `<path-to-pem>` | project-a, project-b |
| Server 2 | `<server-2-ip>` | `<path-to-pem>` | project-c, project-d |

## Workflow

### 1. Determine target
Ask the user or infer from the current project directory:
- Which server IP?
- Which SSH key?
- What's the remote path? (e.g., `/home/ubuntu/oi-dash/`)
- What's the PM2 process name?

### 2. Upload files
```bash
scp -i <pem> -r ./* ubuntu@<ip>:<remote_path>/
```
Exclude `node_modules/`, `.env`, `.git/`, `*.db` unless explicitly requested:
```bash
rsync -avz -e "ssh -i <pem>" --exclude node_modules --exclude .env --exclude .git --exclude '*.db' ./ ubuntu@<ip>:<remote_path>/
```

### 3. Install dependencies (if package.json changed)
```bash
ssh -i <pem> ubuntu@<ip> "cd <remote_path> && npm install --production"
```

### 4. Restart PM2
```bash
ssh -i <pem> ubuntu@<ip> "cd <remote_path> && pm2 restart <process_name>"
```
If process doesn't exist yet:
```bash
ssh -i <pem> ubuntu@<ip> "cd <remote_path> && pm2 start server.js --name <process_name>"
```

### 5. Verify
```bash
ssh -i <pem> ubuntu@<ip> "pm2 status <process_name>"
```
If there's a health endpoint, curl it:
```bash
curl -s http://<ip>:<port>/health || curl -s http://<ip>:<port>/
```

### 6. Check logs if issues
```bash
ssh -i <pem> ubuntu@<ip> "pm2 logs <process_name> --lines 20"
```

## Nginx Setup (if needed for new projects)
```bash
ssh -i <pem> ubuntu@<ip> "sudo nano /etc/nginx/sites-available/<domain>"
```
Standard config: proxy_pass to localhost:<port>, SSL via certbot.

## Key Notes
- Always use `ubuntu@` as the SSH user
- Never upload `.env` files -- they should already exist on the server
- Check `pm2 list` first to see existing processes
- If deploying a new project, run `pm2 save` after starting
- For SSL: `sudo certbot --nginx -d <domain>`
