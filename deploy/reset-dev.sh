#!/usr/bin/env bash
# HARD RESET — SOLO FASE DEV. Uso: bash deploy/reset-dev.sh --yes
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
[ -f "$CONFIG_FILE" ] || { echo "ERROR: falta $CONFIG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${VPS_HOST:?}"; : "${SSH_USER:?}"; : "${SSH_KEY:?}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
if [ "${1:-}" != "--yes" ]; then
  echo "⚠️  HARD RESET (solo DEV): borra todas las guías y correos del tracker en $VPS_HOST"
  echo "    Actualiza START_AFTER para ignorar correos viejos."
  echo "    Para confirmar: bash deploy/reset-dev.sh --yes"
  exit 1
fi
SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
echo "==> Reset tracker en $VPS_HOST ..."
ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" "bash -s" <<'REMOTE'
set -e
cd /opt/tracker/app
docker compose -p tracker stop tracker
VOL="$(docker volume ls -q --filter name=tracker_tracker-data | head -1)"
[ -n "$VOL" ] || { echo "ERROR: no encontré el volumen tracker_tracker-data"; exit 1; }
docker run --rm -v "$VOL":/data alpine sh -c 'rm -rf /data/*.sqlite* /data/emails'
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sed -i "s|^START_AFTER=.*|START_AFTER=$NOW|" /opt/tracker/.secrets /opt/tracker/app/.env
docker compose -p tracker up -d tracker
curl --retry 40 --retry-delay 1 --retry-connrefused -sf http://127.0.0.1:3100/api/v1/health >/dev/null
ADMIN_EMAIL="$(sed -n 's/^ADMIN_EMAIL=//p' /opt/tracker/app/.env)"
ADMIN_PASSWORD="$(sed -n 's/^ADMIN_PASSWORD=//p' /opt/tracker/app/.env)"
TOKEN="$(curl -s -H 'Content-Type: application/json' -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" http://127.0.0.1:3100/api/v1/auth/login | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
TOTAL="$(curl -s -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:3100/api/v1/shipments?page_size=1' | sed -n 's/.*"total":\([0-9]*\).*/\1/p')"
[ -n "$TOTAL" ] || { echo "ERROR: no se pudo verificar (¿falló el login del admin?)" >&2; exit 1; }
echo "total de guías -> $TOTAL"
[ "$TOTAL" = 0 ] || { echo "ERROR: quedaron guías después del reset" >&2; exit 1; }
REMOTE
echo "✅ Reset completado; las guías quedaron en cero."
