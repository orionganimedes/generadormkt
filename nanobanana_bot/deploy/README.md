# Despliegue de NanoBanana Bot (GeneradorDeploy)

Toolkit para publicar el bot en el VPS por SSH y mantenerlo 24/7 con **systemd**.
El despliegue no abre puertos: el bot usa *long polling* saliente contra Telegram,
por eso el healthcheck valida proceso + logs + `getMe`, no un endpoint HTTP.

## Requisitos

- Acceso SSH por clave al VPS (`BatchMode`, sin contraseña interactiva).
- Usuario con `sudo` sin contraseña (para `systemctl` e `install`).
- En el VPS: `python3` con `venv`, `git`, `curl`, `systemd`.
- El `.env` de la aplicación ya creado en:
  `/opt/nanobanana_bot/nanobanana_bot/.env` con `TELEGRAM_TOKEN` y
  `OPENROUTER_API_KEY` (permisos `600`).

## Configuración

```bash
cd nanobanana_bot
cp deploy/deploy.env.example deploy/deploy.env
$EDITOR deploy/deploy.env      # VPS_HOST, VPS_USER, VPS_SSH_KEY, VPS_PROJECT_PATH
chmod 600 deploy/deploy.env
```

`deploy/deploy.env` está ignorado por Git. Los tokens **no** van aquí.

## Uso

```bash
./scripts/deploy.sh --check    # preflight local, no contacta al VPS
./scripts/deploy.sh            # despliegue completo + healthcheck + rollback
./scripts/rollback.sh <commit> # volver a una versión anterior
```

### Qué hace `deploy.sh`

1. **Preflight local**: aborta si algún archivo de código está vacío, falta una
   variable o la clave SSH no es legible.
2. **Preflight remoto**: SSH, usuario, `python3+venv`, `git`, `sudo -n`, `.env`
   completo, espacio en disco y memoria.
3. **Sincronización**: `git fetch + reset --hard origin/<rama>` (método `git`)
   o `rsync --delete` excluyendo `.env`, `venv`, `.git` (método `rsync`).
4. **Dependencias**: crea `venv` si falta e instala `requirements.txt`.
5. **systemd**: instala la unidad con la ruta y el usuario reales, `daemon-reload`,
   `enable` y `restart`.
6. **Healthcheck** con reintentos. Si falla y el método es `git`, revierte al
   commit anterior (`AUTO_ROLLBACK=1`) y vuelve a comprobar.
7. Guarda el log en `logs/deploy-<fecha>.log` e imprime el resumen.

### Códigos de salida

- `0` despliegue exitoso.
- `1` preflight fallido, despliegue fallido o rollback aplicado (el servicio
  puede estar sano, pero la versión nueva no quedó activa).

## Primer despliegue

El método `git` exige que el VPS ya tenga el repositorio clonado:

```bash
# en el VPS, una sola vez
sudo mkdir -p /opt/nanobanana_bot
sudo chown "$USER":"$USER" /opt/nanobanana_bot
git clone https://github.com/orionganimedes/generadormkt /opt/nanobanana_bot
mkdir -p /opt/nanobanana_bot/nanobanana_bot
nano /opt/nanobanana_bot/nanobanana_bot/.env
chmod 600 /opt/nanobanana_bot/nanobanana_bot/.env
```

Si aún no hay repo en el servidor, usa `DEPLOY_METHOD=rsync` para el bootstrap
(sin rollback automático) y luego vuelve a `git`.

## Healthcheck manual

```bash
ssh ubuntu@TU_VPS 'PROJECT_PATH=/opt/nanobanana_bot SERVICE_NAME=nanobanana-bot bash -s' \
  < nanobanana_bot/scripts/healthcheck.sh
```

## Alternativa con Docker

```bash
docker compose -f nanobanana_bot/deploy/docker-compose.yml up -d --build
docker compose -f nanobanana_bot/deploy/docker-compose.yml logs -f
```

No usar systemd y Docker a la vez para el mismo bot: ambos harían long polling
con el mismo token y Telegram devolvería `Conflict: terminated by other getUpdates`.

## Estado y coordinación

Cada despliegue se registra en `.orquestadores/state/generadordeploy.md`.
Antes de desplegar, el preflight remoto actúa como verificación mínima del
estado del servidor que reporta **VPSGanímedes** (recursos y disponibilidad).
