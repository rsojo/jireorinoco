# Despliegue del stack

Script idempotente para desplegar **todo el stack** en un VPS Ubuntu 24.04:

- **Landing** → `https://jireorinoco.com` (+ www)
- **App de facturas** → `https://p2p.jireorinoco.com` (Docker: floci + api + n8n)
- **DeepSeek** como LLM de extracción de facturas
- **OCR_Processor** (FastAPI + Tesseract) en red interna
- **Watcher IMAP**: correo → OCR → DeepSeek → caso

## Requisitos

- **Local:** `bash`, `ssh`, `tar`, `git`, `openssl`.
- **VPS:** Ubuntu 24.04 con Docker (plantilla de Hostinger) y tu llave SSH ya autorizada en `root@VPS_HOST`.
- **DNS:** registros **A** de `@`, `www` y `p2p` apuntando a la IP del VPS (manual en hPanel o por la API de Hostinger).
- Acceso local a los repos privados `automatizacion-facturas` y `Ocr_Processor` (se envían al VPS por `git archive`, sin credenciales en el servidor).

## Uso

```bash
cp deploy/config.example.env deploy/config.env
# edita deploy/config.env con tus valores (VPS, dominio, rutas de repos, DeepSeek, IMAP)

bash deploy/deploy.sh            # despliega todo
# o por pasos:
bash deploy/deploy.sh base       # firewall + nginx + certbot + docker
bash deploy/deploy.sh landing    # landing
bash deploy/deploy.sh facturas   # stack de facturas + DeepSeek
bash deploy/deploy.sh ocr        # OCR_Processor
bash deploy/deploy.sh watcher    # watcher IMAP
bash deploy/deploy.sh ssl        # certificados Let's Encrypt
bash deploy/deploy.sh status     # estado del stack
```

## Notas

- `deploy/config.env` está en `.gitignore` (contiene secretos: key de DeepSeek, contraseña IMAP). **No lo subas.**
- Los **secretos del stack** (JWT, claves de n8n) se generan en el VPS la primera vez y se guardan en `/opt/facturas/.secrets`; en redespliegues se reutilizan.
- Los puertos de los contenedores (api 3000, floci 4566, n8n 5678, ocr 8000) quedan **solo en `127.0.0.1`** (no expuestos a internet); Nginx publica solo lo necesario.
- El watcher es de **solo lectura** del buzón y procesa únicamente correos nuevos con adjunto PDF/PNG/JPG.
- **Titan:** habilita el **acceso IMAP** del buzón antes de correr `watcher`.
- El OCR se construye con un `Dockerfile.deploy` ligero (sin el build en Rust de `pdf-inspector`); usa el motor `hybrid_pdf`.
