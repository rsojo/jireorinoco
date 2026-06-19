#!/usr/bin/env bash
# =============================================================================
# Despliegue completo del stack jireorinoco en un VPS Ubuntu 24.04.
#
#   Landing (jireorinoco.com)  +  App de facturas (p2p.jireorinoco.com)
#   + DeepSeek (LLM)  +  OCR_Processor  +  watcher IMAP (correo -> OCR -> LLM)
#
# Uso:
#   cp deploy/config.example.env deploy/config.env   # y completa los valores
#   bash deploy/deploy.sh [paso]
#
# Pasos: all (def) | base | landing | facturas | ocr | watcher | ssl | status
#
# Requisitos LOCALES: bash, ssh, tar, git, openssl.
# Requisitos VPS: Ubuntu 24.04 con Docker (plantilla de Hostinger) y tu llave
# SSH ya autorizada en root@VPS_HOST.
#
# Prerrequisito DNS (manual o por API): registros A de @, www y p2p -> IP del VPS.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
REMOTE_CONF="/root/.stack-deploy.env"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$CONFIG_FILE" ] || die "No existe $CONFIG_FILE. Copia config.example.env a config.env y complétalo."
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${VPS_HOST:?}"; : "${SSH_USER:?}"; : "${SSH_KEY:?}"; : "${DOMAIN:?}"; : "${CERTBOT_EMAIL:?}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
[ -f "$SSH_KEY" ] || die "No encuentro la llave SSH: $SSH_KEY"

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
remote()      { ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" "$@"; }
remote_bash() { ssh "${SSH_OPTS[@]}" "$SSH_USER@$VPS_HOST" "bash -s"; }   # lee script por stdin

# Envía un repo local (rama/HEAD) y lo extrae en un destino del VPS.
ship_repo() { # <dir_local> <ref> <dest_remoto>
  local dir="$1" ref="$2" dest="$3"
  [ -d "$dir/.git" ] || die "No es un repo git: $dir"
  git -C "$dir" archive --format=tar "$ref" \
    | remote "mkdir -p '$dest' && tar -x -C '$dest'"
}

# --- Publica la configuración (secretos del usuario) en el VPS, una sola vez ---
push_config() {
  log "Publicando configuración en el VPS ($REMOTE_CONF)"
  remote "umask 077; cat > $REMOTE_CONF" <<EOF
DOMAIN='$DOMAIN'
CERTBOT_EMAIL='$CERTBOT_EMAIL'
DEEPSEEK_API_KEY='${DEEPSEEK_API_KEY:-}'
DEEPSEEK_MODEL='${DEEPSEEK_MODEL:-deepseek-chat}'
IMAP_HOST='${IMAP_HOST:-imap.titan.email}'
IMAP_PORT='${IMAP_PORT:-993}'
IMAP_USER='${IMAP_USER:-}'
IMAP_PASS='${IMAP_PASS:-}'
IMAP_POLL_SECONDS='${IMAP_POLL_SECONDS:-60}'
DEFAULT_OCR_LANGUAGE='${DEFAULT_OCR_LANGUAGE:-spa}'
EOF
  ok "config publicada"
}

# =============================================================================
step_base() {
  log "Base: firewall + Nginx + Certbot + Docker"
  remote_bash <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 80/tcp  >/dev/null 2>&1 || true
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

# =============================================================================
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

# =============================================================================
step_facturas() {
  log "Stack de facturas: $FACTURAS_DIR ($FACTURAS_BRANCH) -> p2p.$DOMAIN"
  : "${FACTURAS_DIR:?}"
  ship_repo "$FACTURAS_DIR" "${FACTURAS_BRANCH:-main}" "/opt/facturas"
  remote_bash <<'EOF'
set -e
source /root/.stack-deploy.env
cd /opt/facturas/apps/floci

# Secretos estables (se generan una vez y se reutilizan).
if [ ! -f /opt/facturas/.secrets ] || ! grep -q '^JWT_SECRET=' /opt/facturas/.secrets; then
  umask 077
  { echo "JWT_SECRET=$(openssl rand -hex 32)";
    echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 24)";
    echo "N8N_API_KEY=$(openssl rand -hex 24)"; } >> /opt/facturas/.secrets
fi
source /opt/facturas/.secrets
grep -q '^DEEPSEEK_API_KEY=' /opt/facturas/.secrets || echo "DEEPSEEK_API_KEY=$DEEPSEEK_API_KEY" >> /opt/facturas/.secrets

# 1) flag node:sqlite, 2) puertos solo localhost, 3) secretos, 4) DeepSeek
sed -i 's|node scripts/migrate.js|node --experimental-sqlite scripts/migrate.js|;
        s|node scripts/seed.js|node --experimental-sqlite scripts/seed.js|;
        s|node scripts/bootstrap-floci-s3.js|node --experimental-sqlite scripts/bootstrap-floci-s3.js|;
        s|node src/server.js|node --experimental-sqlite src/server.js|' docker-compose.yml
sed -i 's|- "4566:4566"|- "127.0.0.1:4566:4566"|; s|- "3000:3000"|- "127.0.0.1:3000:3000"|; s|- "5678:5678"|- "127.0.0.1:5678:5678"|' docker-compose.yml
sed -i "s/dev-secret-change-me/$JWT_SECRET/; s/dev-n8n-encryption-key-change-me/$N8N_ENCRYPTION_KEY/; s/n8n-dev-key/$N8N_API_KEY/g" docker-compose.yml
if [ -n "$DEEPSEEK_API_KEY" ]; then
  sed -i "s|AI_PROVIDER: mock|AI_PROVIDER: deepseek\n      DEEPSEEK_API_KEY: \"$DEEPSEEK_API_KEY\"\n      DEEPSEEK_MODEL: \"${DEEPSEEK_MODEL:-deepseek-chat}\"|" docker-compose.yml
fi

docker compose up -d --build

# Nginx p2p: panel web (estático) + proxy /api al api (mismo origen)
cat > "/etc/nginx/sites-available/p2p.$DOMAIN" <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name p2p.__DOMAIN__;
    root /opt/facturas/apps/web;
    index index.html;
    location = /api/config.js { default_type application/javascript; return 200 "window.APP_CONFIG = {\"apiBaseUrl\":\"\"};"; }
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location / { try_files $uri $uri/ =404; }
}
NGINX
sed -i "s/__DOMAIN__/$DOMAIN/g" "/etc/nginx/sites-available/p2p.$DOMAIN"
chmod o+rx /opt /opt/facturas /opt/facturas/apps
ln -sf "/etc/nginx/sites-available/p2p.$DOMAIN" "/etc/nginx/sites-enabled/p2p.$DOMAIN"
nginx -t && systemctl reload nginx
docker compose ps
EOF
  ok "stack de facturas desplegado (http)"
}

# =============================================================================
step_ocr() {
  log "OCR_Processor: $OCR_DIR -> contenedor 'ocr' (red interna)"
  : "${OCR_DIR:?}"
  ship_repo "$OCR_DIR" HEAD "/opt/ocr_processor"
  remote_bash <<'EOF'
set -e
source /root/.stack-deploy.env
cd /opt/ocr_processor
cat > Dockerfile.deploy <<'DOCKER'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr tesseract-ocr-eng tesseract-ocr-spa poppler-utils curl \
    && rm -rf /var/lib/apt/lists/*
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
    networks: [facturas]
volumes: { ocr_tmp: {} }
networks:
  facturas: { name: floci_default, external: true }
YML
docker compose -f docker-compose.deploy.yml up -d --build
docker ps --filter name=ocr-processor --format "{{.Status}}"
EOF
  ok "OCR desplegado"
}

# =============================================================================
step_watcher() {
  log "Watcher IMAP ($IMAP_USER): correo -> OCR -> DeepSeek"
  remote_bash <<'EOF'
set -e
source /root/.stack-deploy.env
source /opt/facturas/.secrets
mkdir -p /opt/facturas/mail-watcher
cat > /opt/facturas/mail-watcher/.env <<ENV
IMAP_HOST=$IMAP_HOST
IMAP_PORT=$IMAP_PORT
IMAP_USER=$IMAP_USER
IMAP_PASS=$IMAP_PASS
API_BASE_URL=http://api:3000
OCR_URL=http://ocr:8000
N8N_API_KEY=$N8N_API_KEY
POLL_SECONDS=$IMAP_POLL_SECONDS
START_AFTER=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ENV
chmod 600 /opt/facturas/mail-watcher/.env

cat > /opt/facturas/mail-watcher/watcher.js <<'JS'
const fs = require('node:fs');
const crypto = require('node:crypto');
const { ImapFlow } = require('imapflow');
const { simpleParser } = require('mailparser');
const { runGmailToBackendFlow } = require('/app/apps/n8n/simulators/gmail_to_backend.js');

const API = process.env.API_BASE_URL || 'http://api:3000';
const OCR_URL = process.env.OCR_URL || 'http://ocr:8000';
const KEY = process.env.N8N_API_KEY || '';
const POLL = Number(process.env.POLL_SECONDS || 60) * 1000;
const START_AFTER = new Date(process.env.START_AFTER || Date.now());
const ALLOWED = new Set(['application/pdf', 'image/png', 'image/jpeg']);
const STATE = '/app/mail-watcher/processed.json';

function loadProcessed() { try { return new Set(JSON.parse(fs.readFileSync(STATE, 'utf8'))); } catch { return new Set(); } }
function saveProcessed(s) { try { fs.writeFileSync(STATE, JSON.stringify([...s].slice(-500))); } catch (e) {} }

function makeTransport() {
  const req = (method) => async (path, body, headers = {}) => {
    const res = await fetch(new URL(path, API), { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: res.status, body: await res.json().catch(() => ({})) };
  };
  return { post: req('POST'), patch: req('PATCH'), get: req('GET') };
}

async function ocrExtract(att) {
  try {
    const fd = new FormData();
    fd.append('file', new Blob([att.content], { type: (att.contentType || 'application/octet-stream') }), att.filename || 'doc');
    const r = await fetch(OCR_URL + '/api/v1/ocr/upload', { method: 'POST', body: fd });
    if (!r.ok) { console.error('OCR HTTP', r.status); return ''; }
    const j = await r.json();
    return j.text || '';
  } catch (e) { console.error('OCR err', e.message); return ''; }
}

async function buildEmail(p) {
  const raw = (p.attachments || []).filter(a => ALLOWED.has((a.contentType || '').toLowerCase()));
  const attachments = [];
  for (const a of raw) {
    const ocrText = await ocrExtract(a);
    attachments.push({
      filename: a.filename || 'adjunto.pdf', mime_type: (a.contentType || 'application/pdf').toLowerCase(),
      file_size: a.size || (a.content ? a.content.length : 0), storage_type: 's3',
      storage_reference: 'attachments/' + crypto.randomUUID() + '_' + (a.filename || 'adjunto'),
      file_hash: crypto.createHash('sha256').update(a.content || Buffer.from('')).digest('hex'),
      text_content: (ocrText && ocrText.trim()) || p.text || p.subject || '(sin contenido)'
    });
  }
  return {
    message_id: p.messageId || ('titan-' + crypto.randomUUID()), thread_id: p.messageId || ('titan-' + crypto.randomUUID()),
    subject: p.subject || '(sin asunto)', body_text: p.text || '',
    from_email: (p.from && p.from.value && p.from.value[0] && p.from.value[0].address) || 'desconocido@correo',
    received_at: (p.date || new Date()).toISOString(), provider_hint: null, attachments
  };
}

async function poll(processed) {
  const client = new ImapFlow({ host: process.env.IMAP_HOST, port: Number(process.env.IMAP_PORT || 993), secure: true, auth: { user: process.env.IMAP_USER, pass: process.env.IMAP_PASS }, logger: false });
  await client.connect();
  await client.mailboxOpen('INBOX', { readOnly: true });
  try {
    const sinceDay = new Date(START_AFTER); sinceDay.setHours(0, 0, 0, 0);
    const uids = await client.search({ since: sinceDay }, { uid: true });
    for (const uid of (uids || [])) {
      const msg = await client.fetchOne(uid, { source: true }, { uid: true });
      if (!msg || !msg.source) continue;
      const p = await simpleParser(msg.source);
      const mid = p.messageId || ('uid-' + uid);
      if (processed.has(mid)) continue;
      const when = p.date ? new Date(p.date) : new Date();
      if (when <= START_AFTER) { processed.add(mid); continue; }
      const email = await buildEmail(p);
      if (!email.attachments.length) { processed.add(mid); saveProcessed(processed); continue; }
      try {
        const out = await runGmailToBackendFlow({ transport: makeTransport(), apiKey: KEY, email, assigneeCandidates: [], duplicateExistingCases: [] });
        console.log(new Date().toISOString(), 'OK', JSON.stringify({ subject: email.subject, from: email.from_email, outcome: out.outcome, case_id: out.case_id || null }));
      } catch (e) { console.error(new Date().toISOString(), 'ERR procesando', email.subject, '|', e.message); }
      processed.add(mid); saveProcessed(processed);
    }
  } finally { try { await client.mailboxClose(); } catch {} await client.logout(); }
}

(async () => {
  console.log('mail-watcher iniciado. Vigilando', process.env.IMAP_USER, 'desde', START_AFTER.toISOString(), '| OCR:', OCR_URL, '| API:', API);
  const processed = loadProcessed();
  for (;;) {
    try { await poll(processed); }
    catch (e) { console.error(new Date().toISOString(), 'POLL_ERR', e.message, '| resp:', e.responseText || '', '| code:', e.code || e.authenticationFailed || ''); }
    await new Promise(r => setTimeout(r, POLL));
  }
})();
JS

cat > /opt/facturas/mail-watcher/docker-compose.yml <<'YML'
services:
  mail-watcher:
    image: node:22-alpine
    container_name: mail-watcher
    working_dir: /app/mail-watcher
    volumes: ["/opt/facturas:/app"]
    env_file: [/opt/facturas/mail-watcher/.env]
    command: sh -c "[ -d /app/node_modules/imapflow ] || npm --prefix /app install --no-save --no-package-lock imapflow mailparser; node watcher.js"
    restart: unless-stopped
    networks: [facturas]
networks:
  facturas: { name: floci_default, external: true }
YML
cd /opt/facturas/mail-watcher && docker compose up -d
EOF
  ok "watcher desplegado"
}

# =============================================================================
step_ssl() {
  log "SSL (Let's Encrypt) para $DOMAIN, www y p2p"
  remote "certbot --nginx -d '$DOMAIN' -d 'www.$DOMAIN' --non-interactive --agree-tos -m '$CERTBOT_EMAIL' --redirect" || \
    log "  (aviso: revisa que el DNS de @ y www apunte al VPS)"
  remote "certbot --nginx -d 'p2p.$DOMAIN' --non-interactive --agree-tos -m '$CERTBOT_EMAIL' --redirect" || \
    log "  (aviso: revisa que el DNS de p2p apunte al VPS)"
  ok "SSL emitido"
}

# =============================================================================
step_status() {
  log "Estado del stack en $VPS_HOST"
  remote_bash <<'EOF'
echo "== contenedores =="; docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "== nginx sites =="; ls /etc/nginx/sites-enabled/
echo "== health api =="; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/health 2>/dev/null || true
echo "== health ocr =="; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/v1/health 2>/dev/null || true
EOF
}

# =============================================================================
STEP="${1:-all}"
log "VPS=$VPS_HOST  DOMAIN=$DOMAIN  paso=$STEP"
case "$STEP" in
  base)     push_config; step_base ;;
  landing)  push_config; step_landing ;;
  facturas) push_config; step_facturas ;;
  ocr)      push_config; step_ocr ;;
  watcher)  push_config; step_watcher ;;
  ssl)      push_config; step_ssl ;;
  status)   step_status ;;
  all)
    push_config
    step_base
    step_landing
    step_facturas
    step_ocr
    step_watcher
    step_ssl
    step_status
    ;;
  *) die "Paso desconocido: $STEP (usa: all|base|landing|facturas|ocr|watcher|ssl|status)" ;;
esac
log "Listo."
