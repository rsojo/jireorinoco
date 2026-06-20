#!/usr/bin/env bash
# =============================================================================
# HARD RESET — SOLO FASE DEV
#
# Borra TODAS las facturas/casos del sistema y deja la base de datos limpia
# con los datos demo (usuarios, roles, proveedores, proyectos). Además resetea
# el watcher de correos para que IGNORE el correo viejo y solo procese lo nuevo.
#
#   ⚠️  DESTRUCTIVO. No usar en producción.
#
# Uso:
#   bash deploy/reset-dev.sh --yes
#
# Requiere deploy/config.env (mismo que deploy.sh: VPS_HOST, SSH_USER, SSH_KEY).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"

[ -f "$CONFIG_FILE" ] || { echo "ERROR: falta $CONFIG_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${VPS_HOST:?}"; : "${SSH_USER:?}"; : "${SSH_KEY:?}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"

if [ "${1:-}" != "--yes" ]; then
  echo "⚠️  HARD RESET (solo DEV): borra TODAS las facturas/casos en $VPS_HOST"
  echo "    Se conservan usuarios y catálogos demo. El watcher ignorará correos viejos."
  echo ""
  echo "    Para confirmar:  bash deploy/reset-dev.sh --yes"
  exit 1
fi

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)

echo "==> Reset en $VPS_HOST ..."
ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" "bash -s" <<'REMOTE'
set -e
cd /opt/facturas/apps/floci

echo "  - Deteniendo api ..."
docker compose stop api

echo "  - Borrando base de datos (casos/facturas) ..."
VOL="$(docker volume ls -q --filter name=api-data | head -1)"
if [ -z "$VOL" ]; then echo "    ERROR: no encontré el volumen api-data"; exit 1; fi
docker run --rm -v "$VOL":/data alpine sh -c "rm -f /data/api.sqlite /data/api.sqlite-wal /data/api.sqlite-shm"

echo "  - Reiniciando api (re-migra + re-siembra datos demo) ..."
docker compose up -d api
curl --retry 40 --retry-delay 1 --retry-connrefused -sf http://127.0.0.1:3000/health >/dev/null && echo "    api OK"

echo "  - Reseteando watcher de correos (ignorar correo viejo) ..."
if [ -f /opt/facturas/mail-watcher/.env ]; then
  sed -i "s|^START_AFTER=.*|START_AFTER=$(date -u +%Y-%m-%dT%H:%M:%SZ)|" /opt/facturas/mail-watcher/.env
  echo '[]' > /opt/facturas/mail-watcher/processed.json
  ( cd /opt/facturas/mail-watcher && docker compose up -d --force-recreate >/dev/null )
  echo "    watcher reiniciado (solo procesará correos nuevos)"
fi
REMOTE

echo ""
echo "==> Verificando que no queden facturas ..."
ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" 'bash -s' <<'REMOTE'
TOK=$(curl -s -H "Content-Type: application/json" -d '{"email":"admin@empresa.com","password":"secret123"}' http://127.0.0.1:3000/api/v1/auth/login | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
N=$(curl -s -H "Authorization: Bearer $TOK" "http://127.0.0.1:3000/api/v1/invoice-cases?page_size=200" | grep -o '"case_number"' | wc -l)
echo "  facturas/casos en el sistema -> $N"
REMOTE

echo "✅ Reset completado. La base quedó limpia (datos demo) y sin facturas."
