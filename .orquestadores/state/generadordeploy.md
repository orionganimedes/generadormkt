# Estado — GeneradorDeploy 🖥️

> Este archivo es actualizado por el agente GeneradorDeploy al completar cada despliegue al VPS.
> Sirve como bitácora de versiones desplegadas, resultados de healthcheck y cualquier rollback ejecutado.

---

## 2026-10-27 — Toolkit de despliegue systemd + preflight (sin despliegue remoto)

**Estado:** FALLIDO (bloqueado en preflight; no se contactó al VPS)
**Versión desplegada:** N/A
**VPS:** N/A — `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` y `VPS_PROJECT_PATH` no definidos
**Comando ejecutado:** `nanobanana_bot/scripts/deploy.sh --check` (exit 1)
**Healthcheck:** NO EJECUTADO (lógica validada en seco)
**Tiempo de despliegue:** 0 s (abortado antes de SSH)

### Motivo del bloqueo

- Código vacío: `bot.py`, `requirements.txt`, `config/settings.py` y
  `services/openrouter_service.py` están en 0 bytes. No hay código aprobado
  por DevGitAuditor que desplegar.
- Sin credenciales: no existe `deploy/deploy.env` ni variables `VPS_*` en el
  entorno; no hay clave SSH configurada.
- Sin `.env` de aplicación en el repositorio (correcto: nunca se versiona).
- Sin commits nuevos desde `45c0ba7b5a2d` en la rama `orionganimedes/python`.
- No se ejecutó ningún comando remoto ni se modificó el VPS.

### Archivos creados/modificados

| Archivo | Contenido |
|---|---|
| `nanobanana_bot/scripts/common.sh` | Colores y logging, carga de `deploy.env`, validación de comandos, construcción de opciones SSH/SCP (`BatchMode`, `ConnectTimeout`, `StrictHostKeyChecking=accept-new`, `IdentitiesOnly`), `ssh_exec`, `remote_healthcheck` y resumen final. |
| `nanobanana_bot/scripts/deploy.sh` | Preflight local (código no vacío + variables + clave legible + ruta absoluta + método válido), preflight remoto (SSH, usuario, `python3+venv`, `git`, `sudo -n`, `.env` completo, disco, RAM, carga), bloqueo con `flock`, snapshot del commit previo, sync `git fetch/reset --hard` o `rsync --delete`, creación de `venv` + `pip install`, instalación de unidad systemd, `daemon-reload`/`enable`/`restart`, healthcheck con reintentos, rollback automático y log en `logs/deploy-<fecha>.log`. |
| `nanobanana_bot/scripts/healthcheck.sh` | Verifica servicio activo, `MainPID`, `cmdline` (`nanobanana_bot.bot`), estabilidad del proceso (`etimes >= 10`), errores fatales en journal (traceback, `InvalidToken`, `Conflict: terminated by other getUpdates`), existencia/permisos de `.env`, `TELEGRAM_TOKEN` y `OPENROUTER_API_KEY`, `getMe` real contra Telegram sin imprimir el token, y espacio en disco. |
| `nanobanana_bot/scripts/rollback.sh` | Rollback manual a commit/tag: valida la referencia con `git cat-file -e`, `reset --hard`, reinicia el servicio y ejecuta healthcheck. |
| `nanobanana_bot/deploy/deploy.env.example` | Variables de acceso SSH, servicio, estrategia (`git`/`rsync`), rama, `ALLOW_DIRTY`, reintentos, `TELEGRAM_HEALTHCHECK` y `AUTO_ROLLBACK`. Sin secretos. |
| `nanobanana_bot/deploy/systemd/nanobanana-bot.service` | Unidad con placeholders `@PROJECT_PATH@`, `@RUN_USER@`, `@RUN_GROUP@`; `EnvironmentFile` apuntando al `.env`; `Restart=always`; *hardening* (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=full`, `ProtectHome=read-only`, `UMask=0077`). |
| `nanobanana_bot/deploy/Dockerfile` | Alternativa a systemd: `python:3.12-slim`, usuario `bot` no root, instala `requirements.txt`, `CMD python -m nanobanana_bot.bot`. |
| `nanobanana_bot/deploy/docker-compose.yml` | Servicio sin puertos (long polling), `env_file: ../.env`, `restart: unless-stopped`, límites de log y healthcheck por proceso. |
| `nanobanana_bot/deploy/README.md` | Requisitos, configuración, uso, qué hace cada fase, primer despliegue, healthcheck manual, alternativa Docker y advertencia de doble polling. |
| `.gitignore` | Añadidos `nanobanana_bot/deploy/deploy.env` y `logs/`. |
| `.orquestadores/state/generadordeploy.md` | Este registro. |
| `arquitecto/.orquestadores/state/devgitauditor.md` | Actualizado con la auditoría pendiente (código vacío). Acción de coordinación, no de código. |

### Validaciones ejecutadas

- `bash -n` en los cuatro scripts: **OK**.
- `./scripts/deploy.sh --check`: **exit 1**, 8 problemas (4 archivos vacíos + 4 variables ausentes). No contactó al VPS.
- Render de la unidad systemd: `ExecStart=/opt/nanobanana_bot/venv/bin/python -m nanobanana_bot.bot`, `EnvironmentFile=/opt/nanobanana_bot/nanobanana_bot/.env`, `User/Group=ubuntu`: **correcto**.
- `healthcheck.sh` en seco (sin systemd): 3 fallos esperados (servicio inactivo, sin `MainPID`, sin `.env`), exit 1, sin errores de sintaxis ni variables sin definir.
- `docker compose config`: **OK** tras corregir `env_file` de `../nanobanana_bot/.env` a `../.env` (validado con un `.env` temporal, eliminado después).
- Permisos `+x` aplicados a los cuatro scripts.

### Decisiones técnicas

- **Healthcheck de proceso, no HTTP**: el bot usa long polling y no abre puertos;
  se valida systemd + PID + journal + `getMe`.
- **`git` como método recomendado**: permite rollback automático al commit previo;
  `rsync` queda para el bootstrap inicial y no revierte solo.
- **Sin `git clean`** en el VPS para no borrar `venv` ni `.env`.
- **Rollback automático** solo si `AUTO_ROLLBACK=1` y el método es `git`.
- **Nunca systemd y Docker a la vez**: el mismo token provocaría
  `Conflict: terminated by other getUpdates`.
- **Secretos**: `deploy.env` ignorado por Git; tokens solo en el `.env` del VPS
  con permisos `600`.
- **Grupo del servicio** resuelto en el VPS con `id -gn` (no se asume que coincida
  con el nombre del usuario).

### Pendiente para desbloquear

1. Python entrega el código (los cuatro archivos siguen vacíos).
2. DevGitAuditor audita y publica en `main`.
3. Copiar `deploy/deploy.env.example` a `deploy/deploy.env` y rellenar `VPS_*`.
4. Crear `/opt/nanobanana_bot/nanobanana_bot/.env` en el VPS con `TELEGRAM_TOKEN`
   y `OPENROUTER_API_KEY` (`chmod 600`).
5. Ejecutar `./scripts/deploy.sh --check` y luego `./scripts/deploy.sh`.

**Próximo agente:** Python (código) → DevGitAuditor (aprobación) → GeneradorDeploy (despliegue).
