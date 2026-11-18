#!/usr/bin/env bash
# =============================================================================
# Despliegue del stack jireorinoco en un VPS Ubuntu 24.04.
#
#   Landing (<DOMAIN>) + Tracker de conciliación (tracker.<DOMAIN>)
#   + OCR opcional para los adjuntos del tracker.
#
# Uso:
#   cp deploy/config.example.env deploy/config.env
#   bash deploy/deploy.sh [paso]
#
# Pasos: all (def) | base | landing | tracker | ocr | ssl | status | retire-p2p
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
REMOTE_CONF="/root/.stack-deploy.env"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$CONFIG_FILE" ] || die "No existe $CONFIG_FILE. Copia config.example.env a config.env y complétalo."
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${VPS_HOST:?}"; : "${SSH_USER:?}"; : "${SSH_KEY:?}"; : "${DOMAIN:?}"; : "${CERTBOT_EMAIL:?}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
[ -f "$SSH_KEY" ] || die "No encuentro la llave SSH: $SSH_KEY"

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
remote() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" "$@"; }
remote_bash() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" "bash -s"; }

ship_repo() {
  local dir="$1" ref="$2" dest="$3"
  [ -d "$dir/.git" ] || die "No es un repo git: $dir"
  git -C "$dir" archive --format=tar "$ref" | remote "mkdir -p '$dest' && tar -x -C '$dest'"
}

push_config() {
  log "Publicando configuración en el VPS ($REMOTE_CONF)"
  {
    printf 'DOMAIN=%q\n' "$DOMAIN"
    printf 'CERTBOT_EMAIL=%q\n' "$CERTBOT_EMAIL"
    printf 'TRACKER_DIR=%q\n' "${TRACKER_DIR:-}"
    printf 'TRACKER_BRANCH=%q\n' "${TRACKER_BRANCH:-main}"
    printf 'TRACKER_SUBDOMAIN=%q\n' "${TRACKER_SUBDOMAIN:-tracker}"
    printf 'TRACKER_SOURCE_EMAIL=%q\n' "${TRACKER_SOURCE_EMAIL:-}"
    printf 'TRACKER_ADMIN_EMAIL=%q\n' "${TRACKER_ADMIN_EMAIL:-admin@$DOMAIN}"
    printf 'TRACKER_ADMIN_PASSWORD=%q\n' "${TRACKER_ADMIN_PASSWORD:-}"
    printf 'TRACKER_ASSIGNMENT_SUBJECT_REGEX=%q\n' "${TRACKER_ASSIGNMENT_SUBJECT_REGEX:-}"
    printf 'TRACKER_PAYMENT_SUBJECT_REGEX=%q\n' "${TRACKER_PAYMENT_SUBJECT_REGEX:-}"
    printf 'TRACKER_IMAP_MAILBOX=%q\n' "${TRACKER_IMAP_MAILBOX:-INBOX}"
    printf 'TRACKER_OCR=%q\n' "${TRACKER_OCR:-false}"
    printf 'DEEPSEEK_API_KEY=%q\n' "${DEEPSEEK_API_KEY:-}"
    printf 'DEEPSEEK_MODEL=%q\n' "${DEEPSEEK_MODEL:-deepseek-chat}"
    printf 'IMAP_HOST=%q\n' "${IMAP_HOST:-imap.titan.email}"
    printf 'IMAP_PORT=%q\n' "${IMAP_PORT:-993}"
    printf 'IMAP_USER=%q\n' "${IMAP_USER:-}"
    printf 'IMAP_PASS=%q\n' "${IMAP_PASS:-}"
    printf 'IMAP_POLL_SECONDS=%q\n' "${IMAP_POLL_SECONDS:-60}"
    printf 'OCR_DIR=%q\n' "${OCR_DIR:-}"
    printf 'DEFAULT_OCR_LANGUAGE=%q\n' "${DEFAULT_OCR_LANGUAGE:-spa}"
  } | remote "umask 077; cat > '$REMOTE_CONF'"
  ok "config publicada"
}

step_base() {
  log "Base: firewall + Nginx + Certbot + Docker"
  remote_bash <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null
systemctl enable --now nginx >/dev/null 2>&1 || true
command -v docker >/dev/null || { curl -fsSL https://get.docker.com | sh; }
echo "nginx: $(nginx -v 2>&1) | docker: $(docker --version) | compose: $(docker compose version | head -1)"
EOF
  ok "base lista"
}

step_landing() {
  log "Landing: $DOMAIN (desde este repo)"
  ship_repo "$REPO_ROOT" HEAD "/var/www/$DOMAIN"
  remote_bash <<'EOF'
set -e
source /root/.stack-deploy.env
cat > "/etc/nginx/sites-available/$DOMAIN" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__ www.__DOMAIN__;
    root /var/www/__DOMAIN__;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
NGINX
sed -i "s/__DOMAIN__/$DOMAIN/g" "/etc/nginx/sites-available/$DOMAIN"
ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
EOF
  ok "landing desplegada (http)"
}

step_tracker() {
  : "${TRACKER_DIR:?TRACKER_DIR es obligatorio para tracker}"
  local branch="${TRACKER_BRANCH:-main}"
  [ -d "$TRACKER_DIR/.git" ] || die "No es un repo git: $TRACKER_DIR"
  git -C "$TRACKER_DIR" show-ref --verify --quiet "refs/heads/$branch" || die "No existe la rama local $branch en $TRACKER_DIR"
  [ -n "${TRACKER_SOURCE_EMAIL:-}" ] || log "Aviso: TRACKER_SOURCE_EMAIL está vacío; el procesador de correo quedará inactivo"
  local revision
  revision="$(git -C "$TRACKER_DIR" rev-parse --short "$branch")"
  log "Tracker: $TRACKER_DIR ($branch) -> ${TRACKER_SUBDOMAIN:-tracker}.$DOMAIN"
  remote "rm -rf /opt/tracker/app.new && mkdir -p /opt/tracker"
  ship_repo "$TRACKER_DIR" "$branch" "/opt/tracker/app.new"
  remote_bash <<EOF
set -e
source /root/.stack-deploy.env
rm -rf /opt/tracker/app.old
[ ! -e /opt/tracker/app ] || mv /opt/tracker/app /opt/tracker/app.old
mv /opt/tracker/app.new /opt/tracker/app
printf '%s\n' '$revision' > /opt/tracker/app/REVISION

for value in "\$TRACKER_ADMIN_EMAIL" "\$TRACKER_ADMIN_PASSWORD" "\$TRACKER_SOURCE_EMAIL" "\$TRACKER_ASSIGNMENT_SUBJECT_REGEX" "\$TRACKER_PAYMENT_SUBJECT_REGEX" "\$IMAP_HOST" "\$IMAP_PORT" "\$IMAP_USER" "\$IMAP_PASS" "\$DEEPSEEK_API_KEY" "\$DEEPSEEK_MODEL"; do
  case "\$value" in *$'\n'*|*$'\r'*) echo "ERROR: los valores del tracker no pueden contener saltos de línea" >&2; exit 1;; esac
done

umask 077
if [ ! -f /opt/tracker/.secrets ] || ! grep -q '^JWT_SECRET=' /opt/tracker/.secrets; then
  ADMIN_PASSWORD="\$TRACKER_ADMIN_PASSWORD"
  GENERATED_ADMIN=0
  if [ -z "\$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="\$(openssl rand -base64 18 | tr -d '/+=')"
    GENERATED_ADMIN=1
  fi
  [ "\${#ADMIN_PASSWORD}" -ge 10 ] || { echo "ERROR: TRACKER_ADMIN_PASSWORD debe tener al menos 10 caracteres" >&2; exit 1; }
  [ "\$ADMIN_PASSWORD" != secret123 ] || { echo "ERROR: TRACKER_ADMIN_PASSWORD no puede ser secret123" >&2; exit 1; }
  { printf 'JWT_SECRET=%s\n' "\$(openssl rand -hex 32)"; printf 'ADMIN_PASSWORD=%q\n' "\$ADMIN_PASSWORD"; printf 'START_AFTER=%s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > /opt/tracker/.secrets
  if [ "\$GENERATED_ADMIN" = 1 ]; then echo "ADMIN_PASSWORD generado: \$ADMIN_PASSWORD (guárdala; no se vuelve a mostrar)"; fi
fi
source /opt/tracker/.secrets
write_env() { printf '%s=%s\n' "\$1" "\$2"; }
{
  write_env NODE_ENV production; write_env PORT 3100; write_env DATA_DIR /data
  write_env JWT_SECRET "\$JWT_SECRET"; write_env ADMIN_EMAIL "\$TRACKER_ADMIN_EMAIL"; write_env ADMIN_PASSWORD "\$ADMIN_PASSWORD"
  if [ -n "\$DEEPSEEK_API_KEY" ]; then write_env EXTRACTOR deepseek; else write_env EXTRACTOR mock; fi
  write_env DEEPSEEK_API_KEY "\$DEEPSEEK_API_KEY"; write_env DEEPSEEK_MODEL "\$DEEPSEEK_MODEL"
  write_env IMAP_HOST "\$IMAP_HOST"; write_env IMAP_PORT "\$IMAP_PORT"; write_env IMAP_USER "\$IMAP_USER"; write_env IMAP_PASS "\$IMAP_PASS"
  write_env IMAP_MAILBOX "\$TRACKER_IMAP_MAILBOX"; write_env POLL_SECONDS "\$IMAP_POLL_SECONDS"; write_env START_AFTER "\$START_AFTER"; write_env SOURCE_EMAIL "\$TRACKER_SOURCE_EMAIL"
  [ -z "\$TRACKER_ASSIGNMENT_SUBJECT_REGEX" ] || write_env ASSIGNMENT_SUBJECT_REGEX "\$TRACKER_ASSIGNMENT_SUBJECT_REGEX"
  [ -z "\$TRACKER_PAYMENT_SUBJECT_REGEX" ] || write_env PAYMENT_SUBJECT_REGEX "\$TRACKER_PAYMENT_SUBJECT_REGEX"
  if [ "\$TRACKER_OCR" = true ]; then write_env OCR_URL http://ocr-processor:8000; fi
} > /opt/tracker/app/.env
chmod 600 /opt/tracker/.secrets /opt/tracker/app/.env
[ -n "\$TRACKER_SOURCE_EMAIL" ] || echo "AVISO: TRACKER_SOURCE_EMAIL está vacío; el procesador de correo quedará inactivo"
cd /opt/tracker/app
# </dev/null: este script llega por stdin (bash -s); sin esto docker compose se "come" el resto del script.
docker compose -p tracker up -d --build --remove-orphans </dev/null
if ! curl --retry 40 --retry-delay 2 --retry-all-errors -sf http://127.0.0.1:3100/api/v1/health >/dev/null; then docker compose -p tracker logs --tail 80 </dev/null; exit 1; fi
cat > "/etc/nginx/sites-available/\$TRACKER_SUBDOMAIN.\$DOMAIN" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name __TRACKER__.__DOMAIN__;
    client_max_body_size 20m;
    location / {
        proxy_pass http://127.0.0.1:3100;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
NGINX
sed -i "s/__TRACKER__/\$TRACKER_SUBDOMAIN/g; s/__DOMAIN__/\$DOMAIN/g" "/etc/nginx/sites-available/\$TRACKER_SUBDOMAIN.\$DOMAIN"
ln -sf "/etc/nginx/sites-available/\$TRACKER_SUBDOMAIN.\$DOMAIN" "/etc/nginx/sites-enabled/\$TRACKER_SUBDOMAIN.\$DOMAIN"
nginx -t && systemctl reload nginx
if [ -d "/etc/letsencrypt/live/\$TRACKER_SUBDOMAIN.\$DOMAIN" ]; then certbot --nginx -d "\$TRACKER_SUBDOMAIN.\$DOMAIN" --non-interactive --reinstall --redirect </dev/null; fi
docker image prune -f </dev/null
echo "tracker OK: revisión \$(cat /opt/tracker/app/REVISION)"
EOF
}

step_ocr() {
  log "OCR_Processor: $OCR_DIR -> contenedor 'ocr-processor' (red tracker_default)"
  : "${OCR_DIR:?}"
  ship_repo "$OCR_DIR" HEAD "/opt/ocr_processor"
  remote_bash <<'EOF'
set -e
source /root/.stack-deploy.env
docker network inspect tracker_default >/dev/null 2>&1 || { echo "ERROR: Despliega primero el tracker" >&2; exit 1; }
cd /opt/ocr_processor
cat > Dockerfile.deploy <<'DOCKER'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-eng tesseract-ocr-spa poppler-utils curl && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1001 appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY ocr_processor/ ocr_processor/
RUN mkdir -p /tmp/ocr_processor && chown appuser:appuser /tmp/ocr_processor
USER appuser
EXPOSE 8000
CMD ["sh","-c","uvicorn ocr_processor.presentation.main:app --host 0.0.0.0 --port 8000 --workers ${WORKERS:-2}"]
DOCKER
cat > .env <<ENV
OCR_ENGINE=hybrid_pdf
TESSERACT_CMD=/usr/bin/tesseract
DEFAULT_OCR_LANGUAGE=${DEFAULT_OCR_LANGUAGE:-spa}
MAX_FILE_SIZE_MB=25
MAX_DOWNLOAD_SIZE_MB=25
DOWNLOAD_TIMEOUT_SECONDS=30
ALLOWED_URL_SCHEMES=["http","https"]
TEMP_DIR=/tmp/ocr_processor
WORKERS=2
LOG_LEVEL=INFO
CORS_ORIGINS=["*"]
ENV
cat > docker-compose.deploy.yml <<'YML'
services:
  ocr:
    build: { context: ., dockerfile: Dockerfile.deploy }
    container_name: ocr-processor
    ports: ["127.0.0.1:8000:8000"]
    env_file: [.env]
    volumes: ["ocr_tmp:/tmp/ocr_processor"]
    restart: unless-stopped
    networks: [tracker]
volumes: { ocr_tmp: {} }
networks:
  tracker: { name: tracker_default, external: true }
YML
docker compose -f docker-compose.deploy.yml up -d --build </dev/null
docker ps --filter name=ocr-processor --format "{{.Status}}"
EOF
  ok "OCR desplegado"
}

step_ssl() {
  log "SSL (Let's Encrypt) para $DOMAIN, www y tracker"
  remote "certbot --nginx -d '$DOMAIN' -d 'www.$DOMAIN' --non-interactive --agree-tos -m '$CERTBOT_EMAIL' --redirect" || log "  (aviso: revisa que el DNS de @ y www apunte al VPS)"
  remote_bash <<'EOF'
set -e
source /root/.stack-deploy.env
NAME="$TRACKER_SUBDOMAIN.$DOMAIN"
DNS_IP="$(getent ahostsv4 "$NAME" | awk 'NR==1 {print $1}')"
VPS_IP="$(curl -s4 --max-time 10 ifconfig.me || hostname -I | awk '{print $1}')"
if [ -z "$DNS_IP" ] || [ "$DNS_IP" != "$VPS_IP" ]; then
  echo "AVISO: crea el registro A $TRACKER_SUBDOMAIN -> $VPS_IP (DNS actual: ${DNS_IP:-no resuelve}); se omite certbot para $NAME"
else
  certbot --nginx -d "$NAME" --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect </dev/null || echo "AVISO: no se pudo emitir el certificado para $NAME"
fi
EOF
  ok "SSL procesado"
}

step_status() {
  log "Estado del stack en $VPS_HOST"
  remote_bash <<'EOF'
source /root/.stack-deploy.env
echo "== contenedores =="; docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "== nginx sites =="; ls /etc/nginx/sites-enabled/
echo "== health tracker =="; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3100/api/v1/health 2>/dev/null || true
echo "== revisión tracker =="; cat /opt/tracker/app/REVISION 2>/dev/null || true
if docker ps -a --format '{{.Names}}' | grep -qx ocr-processor; then
  echo "== health ocr =="; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/v1/health 2>/dev/null || true
fi
echo "== certificados =="; certbot certificates 2>/dev/null | grep -E 'Certificate Name|Expiry' || true
EOF
}

step_retire_p2p() {
  if [ "${1:-}" != "--yes" ]; then
    echo "Este paso retirará el sitio p2p, hará backups y detendrá sus contenedores."
    echo "No borrará los datos guardados ni los volúmenes. Para confirmar: bash deploy/deploy.sh retire-p2p --yes"
    exit 1
  fi
  log "Retirando p2p (conservando /opt/facturas y sus volúmenes)"
  # DOMAIN se antepone escapado: este paso no publica config, así que no depende de /root/.stack-deploy.env.
  { printf 'DOMAIN=%q\n' "$DOMAIN"; cat <<'EOF'
set -e
[ -n "$DOMAIN" ] || { echo "ERROR: DOMAIN vacío" >&2; exit 1; }
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p /root/backups
if [ -d /opt/facturas ]; then
  tar czf "/root/backups/facturas-$STAMP.tgz" --exclude=node_modules -C /opt facturas
  echo "backup: /root/backups/facturas-$STAMP.tgz"
else
  echo "ya retirado: /opt/facturas no existe"
fi
for vol in $(docker volume ls -q | grep '^floci_' || true); do
  docker run --rm -v "$vol:/v" -v /root/backups:/b alpine tar czf "/b/$vol-$STAMP.tgz" -C /v . </dev/null
  echo "backup: /root/backups/$vol-$STAMP.tgz"
done
docker rm -f mail-watcher ocr-processor 2>/dev/null || true
if [ -d /opt/facturas/apps/floci ]; then
  (cd /opt/facturas/apps/floci && docker compose down --remove-orphans </dev/null)
else
  echo "ya retirado: compose no encontrado"
fi
rm -f "/etc/nginx/sites-enabled/p2p.$DOMAIN" "/etc/nginx/sites-available/p2p.$DOMAIN"
nginx -t && systemctl reload nginx
certbot delete --cert-name "p2p.$DOMAIN" --non-interactive </dev/null || true
echo "== backups =="; ls -lh /root/backups/*"$STAMP"* 2>/dev/null || true
echo "No se borraron /opt/facturas ni los volúmenes. Para purgar manualmente: rm -rf /opt/facturas; docker volume rm <volumen>."
echo "Recuerda borrar el registro DNS p2p en Hostinger."
EOF
  } | remote_bash
}

STEP="${1:-all}"
case "$STEP" in
  base) push_config; step_base ;;
  landing) push_config; step_landing ;;
  tracker) push_config; step_tracker ;;
  ocr) push_config; step_ocr ;;
  ssl) push_config; step_ssl ;;
  status) step_status ;;
  retire-p2p) step_retire_p2p "${2:-}" ;;
  all) push_config; step_base; step_landing; step_tracker; step_ssl; step_status ;;
  *) die "Paso desconocido: $STEP (usa: all|base|landing|tracker|ocr|ssl|status|retire-p2p)" ;;
esac
log "Listo."
