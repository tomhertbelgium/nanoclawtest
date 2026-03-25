#!/usr/bin/env bash
# webapp-deploy.sh — Deploy/kill/list static web projects
# Called by NanoClaw IPC handler. Outputs JSON to stdout.
set -euo pipefail

APPS_DIR="/home/tom_mortsel/apps"
ARCHIVE_DIR="${APPS_DIR}/.archive"
PORTS_FILE="${APPS_DIR}/.ports.json"
CADDY_SITES="/etc/caddy/sites"
CADDYFILE="/etc/caddy/Caddyfile"
DOMAIN="intellilab.dev"
PORT_START=9100
MAX_PROJECTS=20

error() { echo "{\"status\":\"error\",\"message\":\"$1\"}"; exit 0; }

# Ensure dirs and ports file exist
mkdir -p "${APPS_DIR}" "${ARCHIVE_DIR}"
[ -f "${PORTS_FILE}" ] || echo '{}' > "${PORTS_FILE}"

ACTION="${1:-}"
NAME="${2:-}"

case "${ACTION}" in
  deploy)
    # Validate name
    if [[ ! "${NAME}" =~ ^[a-z0-9][a-z0-9-]{0,49}$ ]]; then
      error "Invalid name: must be lowercase alphanumeric with hyphens, 1-50 chars"
    fi

    # Check project files exist
    if [ ! -f "${APPS_DIR}/${NAME}/index.html" ]; then
      error "No index.html found at ${APPS_DIR}/${NAME}/"
    fi

    # Check if already deployed
    if docker ps --format '{{.Names}}' | grep -q "^webapp-${NAME}$"; then
      error "Project ${NAME} is already deployed. Kill it first to redeploy."
    fi

    # Check project limit
    ACTIVE=$(docker ps --filter "name=webapp-" --format '{{.Names}}' | wc -l)
    if [ "${ACTIVE}" -ge "${MAX_PROJECTS}" ]; then
      error "Maximum ${MAX_PROJECTS} active projects reached"
    fi

    # Find next available port
    PORT=${PORT_START}
    while true; do
      if ! jq -e "to_entries[] | select(.value == ${PORT})" "${PORTS_FILE}" > /dev/null 2>&1; then
        break
      fi
      PORT=$((PORT + 1))
      if [ "${PORT}" -gt $((PORT_START + 100)) ]; then
        error "No available ports"
      fi
    done

    # Start nginx container
    docker run -d --name "webapp-${NAME}" \
      -p "127.0.0.1:${PORT}:80" \
      -v "${APPS_DIR}/${NAME}:/usr/share/nginx/html:ro" \
      nginx:alpine > /dev/null 2>&1 || error "Failed to start container"

    # Write Caddy site config
    cat <<CADDY | sudo tee "${CADDY_SITES}/${NAME}.caddy" > /dev/null
handle_path /${NAME}/* {
    reverse_proxy localhost:${PORT}
}
CADDY

    # Reload Caddy
    sudo /usr/bin/caddy reload --config "${CADDYFILE}" 2>/dev/null || true

    # Update ports file
    jq --arg name "${NAME}" --argjson port "${PORT}" '. + {($name): $port}' "${PORTS_FILE}" > "${PORTS_FILE}.tmp"
    mv "${PORTS_FILE}.tmp" "${PORTS_FILE}"

    echo "{\"status\":\"ok\",\"url\":\"https://${DOMAIN}/${NAME}/\",\"port\":${PORT}}"
    ;;

  kill)
    if [ -z "${NAME}" ]; then
      error "Name required for kill"
    fi

    # Stop container (ignore errors if not running)
    docker stop "webapp-${NAME}" > /dev/null 2>&1 || true
    docker rm "webapp-${NAME}" > /dev/null 2>&1 || true

    # Remove Caddy config
    sudo /bin/rm "${CADDY_SITES}/${NAME}.caddy" 2>/dev/null || true

    # Reload Caddy
    sudo /usr/bin/caddy reload --config "${CADDYFILE}" 2>/dev/null || true

    # Archive project files
    if [ -d "${APPS_DIR}/${NAME}" ]; then
      mv "${APPS_DIR}/${NAME}" "${ARCHIVE_DIR}/${NAME}-$(date +%s)"
    fi

    # Remove from ports file
    jq --arg name "${NAME}" 'del(.[$name])' "${PORTS_FILE}" > "${PORTS_FILE}.tmp"
    mv "${PORTS_FILE}.tmp" "${PORTS_FILE}"

    echo "{\"status\":\"ok\",\"message\":\"Project ${NAME} removed and archived\"}"
    ;;

  list)
    # Build list from ports file cross-referenced with running containers
    RUNNING=$(docker ps --filter "name=webapp-" --format '{{.Names}}' 2>/dev/null | sed 's/^webapp-//' || true)

    jq --arg domain "${DOMAIN}" --arg running "${RUNNING}" '
      ($running | split("\n")) as $r |
      to_entries | map({
        name: .key,
        url: ("https://" + $domain + "/" + .key + "/"),
        port: .value,
        running: ([.key] | inside($r))
      })
    ' "${PORTS_FILE}"
    ;;

  *)
    error "Unknown action: ${ACTION}. Use deploy, kill, or list."
    ;;
esac
