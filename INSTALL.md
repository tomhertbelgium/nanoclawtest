# NanoClaw — Fresh Install Guide

How to restore NanoClaw on a fresh Debian/Ubuntu VM from the git repository.

**Prerequisites:** A VM with a public IP, DNS pointing to it, and SSH access.

---

## 1. Clone the repo

```bash
git clone https://github.com/tomhertbelgium/nanoclawtest.git nanoclaw
cd nanoclaw
git remote add upstream https://github.com/qwibitai/nanoclaw.git
```

## 2. Install Node.js 22

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

## 3. Install dependencies and build

```bash
npm install
npm run build
```

## 4. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in, or run:
sudo setfacl -m u:$(whoami):rw /var/run/docker.sock
```

## 5. Build the agent container

```bash
./container/build.sh
```

Pre-pull the nginx image used for webapp deployments:

```bash
docker pull nginx:alpine
```

## 6. Install OneCLI (credential management)

```bash
curl -fsSL onecli.sh/install | sh
curl -fsSL onecli.sh/cli/install | sh
export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
onecli config set api-host http://127.0.0.1:10254
```

## 7. Configure credentials

Add your Anthropic API key or Claude subscription token:

```bash
# For API key:
onecli secrets create --name Anthropic --type anthropic --value YOUR_KEY --host-pattern api.anthropic.com

# For Claude subscription token (get it via `claude setup-token`):
onecli secrets create --name Anthropic --type anthropic --value YOUR_TOKEN --host-pattern api.anthropic.com
```

Verify: `onecli secrets list`

## 8. Create .env

```bash
cat > .env << 'EOF'
ONECLI_URL=http://127.0.0.1:10254
TZ=UTC
ASSISTANT_NAME="Claw"
EOF

mkdir -p data/env && cp .env data/env/env
```

## 9. Create mount allowlist and directories

The agent containers can access mounted host directories. Configure which ones:

```bash
mkdir -p ~/.config/nanoclaw
cat > ~/.config/nanoclaw/mount-allowlist.json << 'EOF'
{
  "allowedRoots": [
    "/home/tom_mortsel/apps",
    "/home/tom_mortsel/projects",
    "/home/tom_mortsel/documentation"
  ],
  "blockedPatterns": [],
  "nonMainReadOnly": true
}
EOF

mkdir -p ~/apps ~/projects ~/documentation
```

> Adjust the paths to match your setup. `nonMainReadOnly: true` means non-main groups get read-only access.

## 10. Set up WhatsApp

Run the setup skill in Claude Code (`/setup`) or manually:

```bash
npx tsx setup/index.ts --step whatsapp-auth -- --method pairing-code --phone YOUR_PHONE_NUMBER
```

Then register your chat:

```bash
npx tsx setup/index.ts --step register \
  --jid "YOUR_PHONE@s.whatsapp.net" \
  --name "main" \
  --trigger "@Claw" \
  --folder "whatsapp_main" \
  --channel whatsapp \
  --assistant-name "Claw" \
  --is-main \
  --no-trigger-required
```

## 11. Install Caddy (reverse proxy for webapp deployer)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

Configure Caddy:

```bash
sudo mkdir -p /etc/caddy/sites

# If behind a load balancer (TLS terminated at LB):
sudo tee /etc/caddy/Caddyfile << 'EOF'
:80 {
    import /etc/caddy/sites/*.caddy
    respond "intellilab.dev — nothing here yet" 404
}
EOF

# If Caddy handles TLS directly (no LB):
# sudo tee /etc/caddy/Caddyfile << 'EOF'
# intellilab.dev {
#     import /etc/caddy/sites/*.caddy
#     respond "intellilab.dev — nothing here yet" 404
# }
# EOF

sudo systemctl restart caddy
```

Set up sudoers for the deploy script:

```bash
sudo tee /etc/sudoers.d/nanoclaw-webapp << 'EOF'
YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/caddy reload --config /etc/caddy/Caddyfile
YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/caddy/sites/*
YOUR_USERNAME ALL=(ALL) NOPASSWD: /bin/rm /etc/caddy/sites/*.caddy
EOF
sudo chmod 440 /etc/sudoers.d/nanoclaw-webapp
```

Create the apps directory:

```bash
mkdir -p ~/apps/.archive
```

## 12. Disable Apache (if installed)

```bash
sudo systemctl stop apache2
sudo systemctl disable apache2
```

## 13. Create systemd service

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/nanoclaw.service << EOF
[Unit]
Description=NanoClaw Personal Assistant
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node $(pwd)/dist/index.js
WorkingDirectory=$(pwd)
Restart=always
RestartSec=5
KillMode=process
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin
StandardOutput=append:$(pwd)/logs/nanoclaw.log
StandardError=append:$(pwd)/logs/nanoclaw.error.log

[Install]
WantedBy=default.target
EOF

mkdir -p logs
systemctl --user daemon-reload
systemctl --user enable nanoclaw
systemctl --user start nanoclaw
```

Enable lingering so the service runs without an active login session:

```bash
sudo loginctl enable-linger $(whoami)
```

## 14. Verify

```bash
systemctl --user status nanoclaw
tail -f logs/nanoclaw.log
```

Send a message on WhatsApp — the assistant should respond.

---

## What's NOT in git (lost on VM destruction)

| Data | Location | In git? | Recovery |
|------|----------|---------|----------|
| WhatsApp auth session | `store/auth/` | No | Re-pair via pairing code |
| Message history | `store/messages.db` | No | Lost unless backed up |
| `.env` config | `.env` | No | Recreate (see step 8) |
| Mount allowlist | `~/.config/nanoclaw/` | No | Recreate (see step 9) |
| OneCLI binary | `~/.local/bin/onecli` | No | Re-download (see step 6) |
| OneCLI secrets | managed by OneCLI | No | Re-add API key/token (see step 7) |
| systemd unit | `~/.config/systemd/user/` | No | Recreate (see step 13) |
| Docker image | local Docker | No | Rebuild with `./container/build.sh` |
| Deployed webapps | `~/apps/` | No | Re-create via Claw |
| Group data (non-main) | `groups/*/` | Partially | `whatsapp_main/` etc. not tracked |
| `node_modules/` + `dist/` | repo | No | `npm install && npm run build` |
| Agent session state | `data/sessions/` | No | Auto-recreated on first run |

## Backup

Back up critical state that can't be recreated:

```bash
# Run from home directory. Creates a timestamped backup tarball.
tar czf ~/nanoclaw-backup-$(date +%Y%m%d).tar.gz \
  nanoclaw/store/auth/ \
  nanoclaw/store/messages.db \
  nanoclaw/.env \
  nanoclaw/groups/ \
  .config/nanoclaw/
```

To automate daily backups:

```bash
crontab -e
# Add this line:
0 3 * * * tar czf /home/tom_mortsel/nanoclaw-backup-$(date +\%Y\%m\%d).tar.gz -C /home/tom_mortsel nanoclaw/store/auth/ nanoclaw/store/messages.db nanoclaw/.env nanoclaw/groups/ .config/nanoclaw/ 2>/dev/null
```

> Consider copying backups off-machine (e.g. `gsutil cp`, `scp`, or a mounted cloud drive).

## Restore from backup on a fresh VM

If you have a backup tarball:

1. Follow steps 1-8 above (clone, install Node, Docker, OneCLI, build)
2. Restore the backup:

```bash
cd ~
tar xzf nanoclaw-backup-YYYYMMDD.tar.gz
```

3. Re-add your Anthropic credential to OneCLI (step 7) — secrets are not in the backup
4. Copy env to data dir: `mkdir -p ~/nanoclaw/data/env && cp ~/nanoclaw/.env ~/nanoclaw/data/env/env`
5. Rebuild the container: `cd ~/nanoclaw && ./container/build.sh`
6. Set up systemd (step 13) and start the service
7. Verify with `systemctl --user status nanoclaw`

The WhatsApp session from the backup *may* still be valid. If not, re-pair (step 10).

## Restore WITHOUT a backup (fresh start)

Follow all steps 1-14 sequentially. You'll need to:
- Re-pair WhatsApp (new session)
- Re-add your API credential to OneCLI
- Message history starts fresh
