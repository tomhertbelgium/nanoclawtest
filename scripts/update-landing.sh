#!/usr/bin/env bash
# Regenerate the landing page index.html from the ports file
set -euo pipefail

APPS_DIR="/home/tom_mortsel/apps"
PORTS_FILE="${APPS_DIR}/.ports.json"
LANDING_DIR="${APPS_DIR}/.landing"
DOMAIN="intellilab.dev"

mkdir -p "${LANDING_DIR}"

# Build app cards HTML from ports file
APPS_HTML=""
if [ -f "${PORTS_FILE}" ] && [ "$(jq 'length' "${PORTS_FILE}")" -gt 0 ]; then
  APPS_HTML=$(jq -r --arg domain "${DOMAIN}" '
    to_entries | sort_by(.key)[] |
    "<a class=\"app\" href=\"https://\($domain)/\(.key)/\"><div class=\"app-name\">\(.key)</div><div class=\"app-url\">\($domain)/\(.key)/</div></a>"
  ' "${PORTS_FILE}")
else
  APPS_HTML='<p class="empty">No apps deployed yet.</p>'
fi

cat > "${LANDING_DIR}/index.html" <<'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="robots" content="noindex, nofollow">
  <title>intellilab.dev</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0a0a0a;
      color: #e0e0e0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 3rem 1.5rem;
    }
    h1 { font-size: 2rem; font-weight: 300; letter-spacing: 0.05em; margin-bottom: 0.5rem; color: #fff; }
    .subtitle { color: #666; font-size: 0.9rem; margin-bottom: 3rem; }
    .apps {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 1rem;
      width: 100%;
      max-width: 720px;
    }
    .app {
      display: block;
      padding: 1.25rem 1.5rem;
      background: #151515;
      border: 1px solid #222;
      border-radius: 8px;
      text-decoration: none;
      color: #e0e0e0;
      transition: border-color 0.2s, background 0.2s;
    }
    .app:hover { border-color: #444; background: #1a1a1a; }
    .app-name { font-size: 1.1rem; font-weight: 500; color: #fff; }
    .app-url { font-size: 0.8rem; color: #555; margin-top: 0.25rem; }
    .empty { color: #444; font-style: italic; }
  </style>
</head>
<body>
  <h1>intellilab.dev</h1>
  <p class="subtitle">Apps deployed by Claw</p>
  <div class="apps">
HEADER

echo "${APPS_HTML}" >> "${LANDING_DIR}/index.html"

cat >> "${LANDING_DIR}/index.html" <<'FOOTER'
  </div>
</body>
</html>
FOOTER
