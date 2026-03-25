# Web App Deployer — Plan

**Goal:** Send Claw an idea via WhatsApp, get a fully deployed web app at `intellilabs.dev/<name>/`.

**Example flow:**
> **You:** Hey Claw, I want to create a student portfolio page that's impressive for a first job in real estate
> **Claw:** Great idea! A few questions: 1) What's your name? 2) Any specific projects to highlight? 3) Preferred color scheme?
> **You:** Tom, two university projects on urban planning, dark/modern theme. Call it "tom-portfolio"
> **Claw:** Done! Your portfolio is live at intellilabs.dev/tom-portfolio/
>
> **You:** kill tom-portfolio
> **Claw:** Removed tom-portfolio and its container.

---

## Architecture

```
WhatsApp → NanoClaw → Agent Container → writes files to /apps/<name>/
                                       → IPC deploy command to host
                          Host → builds & starts project container
                               → Caddy auto-routes intellilabs.dev/<name>/
```

### Components

| Component | Role |
|-----------|------|
| **Caddy** (host) | Reverse proxy with auto-HTTPS. Routes `intellilabs.dev/<name>/` to the right container |
| **Project containers** | Lightweight `nginx:alpine` containers serving static files |
| **Deploy script** (host) | Builds/starts/stops project containers, updates Caddy config |
| **IPC deploy tool** | New MCP tool so the agent can trigger deploys from inside its container |
| **Container skill** | Instructions for Claw on how to generate and deploy web projects |

---

## Step 1: Install Caddy as Reverse Proxy

Caddy handles HTTPS automatically (Let's Encrypt) and has simple config.

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy
```

**Caddyfile** (`/etc/caddy/Caddyfile`):

```caddy
intellilabs.dev {
    # Import per-project route configs
    import /etc/caddy/sites/*.caddy

    # Default: landing page or 404
    respond "intellilabs.dev — nothing here yet" 404
}
```

Each project gets a config snippet at `/etc/caddy/sites/<name>.caddy`:

```caddy
handle_path /<name>/* {
    reverse_proxy localhost:<port>
}
```

When a project is added/removed, reload Caddy: `sudo caddy reload --config /etc/caddy/Caddyfile`

**Port allocation:** Use a simple port file at `/home/tom_mortsel/apps/.ports.json` mapping `name → port`, starting at 9100 and incrementing.

---

## Step 2: Deploy Script on Host

A shell script at `/home/tom_mortsel/nanoclaw/scripts/webapp-deploy.sh` that the host process calls when it receives a deploy IPC command.

**Actions:**

### `deploy <name>`
1. Validate `<name>` (alphanumeric + hyphens only, max 50 chars)
2. Verify `/home/tom_mortsel/apps/<name>/` exists and has an `index.html`
3. Allocate a port from the port pool
4. Start a Docker container:
   ```bash
   docker run -d --rm \
     --name "webapp-${name}" \
     -p 127.0.0.1:${port}:80 \
     -v /home/tom_mortsel/apps/${name}:/usr/share/nginx/html:ro \
     nginx:alpine
   ```
5. Write Caddy site config to `/etc/caddy/sites/${name}.caddy`
6. Reload Caddy
7. Return the URL

### `kill <name>`
1. Stop and remove Docker container `webapp-${name}`
2. Remove Caddy site config
3. Reload Caddy
4. Optionally remove files from `/home/tom_mortsel/apps/<name>/` (or archive them)
5. Free the port

### `list`
Return all active projects with their URLs.

**Permissions:** The deploy script needs `sudo caddy reload` access. Add a sudoers rule:
```
tom_mortsel ALL=(ALL) NOPASSWD: /usr/bin/caddy reload --config /etc/caddy/Caddyfile
```

---

## Step 3: New IPC Tool — `deploy_webapp`

Add a new MCP tool to the NanoClaw IPC system so the agent can trigger deployments from inside its container.

**New MCP tools:**

| Tool | Parameters | Action |
|------|-----------|--------|
| `deploy_webapp` | `name` | Deploy project at `/apps/<name>/` |
| `kill_webapp` | `name` | Remove project and container |
| `list_webapps` | — | List active projects with URLs |

**Implementation:** Extend `src/ipc.ts` to handle a new IPC message type `webapp`. When the host receives a `webapp` IPC file, it runs the deploy script.

**File:** Agent writes to `/workspace/ipc/tasks/webapp-<timestamp>.json`:
```json
{
  "type": "webapp",
  "action": "deploy",
  "name": "tom-portfolio"
}
```

Host picks it up, runs the deploy script, and writes the result back.

**Security:** Only the main group can deploy/kill webapps (same authorization pattern as `register_group`).

---

## Step 4: Container Skill for Claw

A container skill at `container/skills/webapp-deployer/` that teaches Claw how to:

1. **Understand the request** — ask clarifying questions (purpose, audience, style preferences, project name)
2. **Generate the project** — create a complete static website in `/workspace/extra/apps/<name>/`
   - `index.html` — main page
   - `styles.css` — styling
   - `script.js` — interactivity if needed
   - `assets/` — images (can use placeholder services or generate SVGs)
3. **Deploy** — call the `deploy_webapp` MCP tool
4. **Report** — send the URL back via WhatsApp

**Skill CLAUDE.md** would include:
- Always ask for a project name (or suggest one)
- Generate modern, responsive HTML/CSS (no build step needed)
- Use CDN-hosted libraries if needed (Tailwind CSS, Alpine.js, etc.)
- Always include `index.html` at the root
- After writing files, call `deploy_webapp` to go live
- Handle "kill <name>" by calling `kill_webapp`

---

## Step 5: WhatsApp "kill" Command

When user sends `kill <name>`, Claw calls `kill_webapp` with the name and confirms removal. This doesn't need code changes — the container skill instructions teach Claw to recognize "kill X" and call the MCP tool.

---

## Step 6: DNS & Firewall

**DNS:** Point `intellilabs.dev` A record to this VM's external IP (GCP). May already be done — verify.

**Firewall:** Ensure GCP firewall allows inbound TCP 80 and 443 to this VM. Caddy handles HTTPS via Let's Encrypt automatically.

```bash
# Check external IP
curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google"

# Verify DNS
dig intellilabs.dev +short
```

---

## Implementation Order

| Phase | What | Effort |
|-------|------|--------|
| **1** | Install Caddy, configure for intellilabs.dev | ~15 min |
| **2** | Write deploy script (`deploy`, `kill`, `list`) | ~30 min |
| **3** | Add IPC `webapp` tool to NanoClaw host process | ~1 hour |
| **4** | Add MCP tool definition in container agent-runner | ~30 min |
| **5** | Create container skill with instructions for Claw | ~30 min |
| **6** | DNS/firewall verification | ~10 min |
| **7** | End-to-end test from WhatsApp | ~15 min |

---

## Alternatives Considered

**Why not have the agent run Docker directly?**
The agent runs inside a container with no Docker socket access. This is by design — it's a security boundary. The IPC approach keeps the agent sandboxed while still enabling host-side actions through a controlled interface.

**Why Caddy over Nginx?**
Automatic HTTPS, simpler config syntax, and easy programmatic reloads. Nginx would work too but needs more manual cert management.

**Why per-project Docker containers instead of a single static file server?**
Isolation. Each project is independently startable/stoppable. If a project includes server-side code later (e.g., Node.js apps), the container approach scales naturally. Also makes "kill" clean — just stop the container.

---

## Decisions

1. **"kill" archives files** to `/apps/.archive/<name>/` rather than deleting them permanently.
2. **Max 20 active projects.** Deploy script refuses new projects beyond this limit.
3. **Main-only.** Only the main group can deploy/kill webapps.
4. **Auto-generated landing page** at `intellilabs.dev/` listing all active projects with links.
