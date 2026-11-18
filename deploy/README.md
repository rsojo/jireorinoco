# Despliegue del stack

Scripts para desplegar en Ubuntu 24.04 la landing y el tracker de conciliación de guías:

- Landing: `https://jireorinoco.com` y `www`.
- Tracker: `https://tracker.jireorinoco.com`, panel y API en el mismo servicio.
- OCR opcional: `Ocr_Processor` en la red privada del tracker.

## Requisitos

- Local: `bash`, `ssh`, `tar`, `git` y `openssl`.
- VPS: Ubuntu 24.04 con Docker y la llave SSH autorizada.
- DNS: registros A de `@`, `www` y `tracker` apuntando al VPS.
- Acceso local a `guias-conciliacion` y, si se usa, `Ocr_Processor`.

Copia `deploy/config.example.env` a `deploy/config.env` y completa los valores.

## Uso

```bash
bash deploy/deploy.sh              # all: base, landing, tracker, SSL y estado
bash deploy/deploy.sh base
bash deploy/deploy.sh landing
bash deploy/deploy.sh tracker
bash deploy/deploy.sh ocr           # opcional; requiere tracker desplegado
bash deploy/deploy.sh ssl
bash deploy/deploy.sh status
```

`all` no despliega OCR ni retira el sitio anterior. El paso `retire-p2p` es independiente y no publica configuración.

## Retirar el sitio anterior

```bash
bash deploy/deploy.sh retire-p2p --yes
```

Guarda backups del sitio y de los volúmenes, detiene contenedores, elimina Nginx y certificado, y muestra los archivos y tamaños. No borra los volúmenes ni `/opt/facturas`; el registro DNS debe borrarse manualmente en Hostinger.

## Reset de desarrollo

```bash
bash deploy/reset-dev.sh --yes
```

Detiene el tracker, borra la base y los `.eml`, actualiza `START_AFTER`, arranca y verifica login y total cero. No usar en producción.

## Notas

- Los secretos estables viven en `/opt/tracker/.secrets`; el admin generado se muestra una sola vez.
- `START_AFTER` se fija en el primer despliegue para no procesar correos anteriores.
- El watcher integrado solo lee el remitente `TRACKER_SOURCE_EMAIL`; vacío lo deja inactivo.
- El puerto 3100 solo escucha en localhost; Nginx publica el tracker.
