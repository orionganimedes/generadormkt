# 🚀 Guía de Trabajo e Implementación — NanoBanana Bot

Este documento detalla la estructura, flujo de trabajo, configuración y procedimiento de despliegue en producción del proyecto **NanoBanana Bot** en el VPS.

---

## 1. 📌 Información del Servidor VPS

- **Host / IP:** `37.60.242.14` (`vps-ganimedes` / `ganimedesvps`)
- **Usuario SSH:** `ganimedes`
- **Ruta de Despliegue en VPS:** `/home/ganimedes/ganimedesmkt`
- **Autenticación:** Llave SSH Ed25519 (`~/.ssh/id_ed25519`)
- **Gestión de Procesos:** Systemd (`nanobanana-bot.service`) con soporte alternativo Docker Compose

---

## 2. 🏗️ Arquitectura y Pipeline de Orquestación

El proyecto opera con una división de responsabilidades coordinada por agentes:

```
[Arquitecto] ──> [Python] ──> [DevGitAuditor] ──> [GeneradorDeploy]
                                                        │ (coordina)
                                                        ▼
                                                 [VPSGanímedes]
```

1. **Arquitecto:** Define especificaciones, estructura de carpetas y contratos de API.
2. **Python:** Implementa la lógica del bot (`bot.py`), integraciones con APIs (`services/openrouter_service.py`), configuración (`config/settings.py`) y librerías (`requirements.txt`).
3. **DevGitAuditor:** Audita seguridad (sin secretos expuestos, sin inyecciones), estándares PEP8, control de ramas Git, commits y tests.
4. **GeneradorDeploy & VPSGanímedes:** Sincronizan el código, configuran el entorno virtual (`venv`), instalan dependencias, configuran unidades `systemd` y validan el healthcheck en el VPS.

---

## 3. 📂 Estructura del Proyecto Desplegado

```bash
/home/ganimedes/ganimedesmkt/
├── .gitignore
├── TRABAJO_E_IMPLEMENTACION.md
├── .orquestadores/
│   ├── gu_a_de_implementaci_n_python.md
│   ├── orquestaci_n_de_agentes.md
│   ├── prompts/
│   │   ├── arquitecto.md
│   │   ├── python.md
│   │   ├── devgitauditor.md
│   │   ├── vpsganimedes.md
│   │   └── generadordeploy.md
│   └── state/
│       ├── arquitecto.md
│       ├── python.md
│       ├── devgitauditor.md
│       ├── vpsganimedes.md
│       └── generadordeploy.md
└── nanobanana_bot/
    ├── bot.py
    ├── requirements.txt
    ├── .env.example
    ├── config/
    │   └── settings.py
    ├── services/
    │   └── openrouter_service.py
    ├── scripts/
    │   ├── common.sh        # Funciones auxiliares y conexiones SSH seguras
    │   ├── deploy.sh        # Orquestador del despliegue, preflight y sync
    │   ├── healthcheck.sh   # Comprobación de salud (systemd, PID, API Telegram)
    │   └── rollback.sh      # Reversión a commits previos
    └── deploy/
        ├── deploy.env.example # Plantilla de variables de conexión
        ├── README.md          # Manual del toolkit de despliegue
        ├── Dockerfile         # Imagen contenerizada
        ├── docker-compose.yml # Despliegue con Docker Compose
        └── systemd/
            └── nanobanana-bot.service # Servicio Linux con hardening
```

---

## 4. ⚙️ Toolkit de Despliegue

### A. Scripts de Automatización (`nanobanana_bot/scripts/`)
- **`deploy.sh`**:
  - Verifica variables locales y código previo al envío.
  - Sincroniza archivos vía `rsync` o `git`.
  - Configura el entorno virtual `venv` e instala dependencias (`pip`).
  - Instala/actualiza la unidad Systemd y ejecuta `systemctl daemon-reload` y `systemctl restart`.
  - Ejecuta el healthcheck posdespliegue con soporte de rollback automático.
- **`healthcheck.sh`**:
  - Valida que el proceso esté activo (`systemctl is-active`).
  - Inspecciona `MainPID` y `cmdline`.
  - Verifica que los tokens de entorno (`TELEGRAM_TOKEN`, `OPENROUTER_API_KEY`) estén cargados.
  - Consulta `getMe` contra la API de Telegram de forma segura.
- **`rollback.sh`**: Permite revertir de forma limpia a un commit o tag previo ante incidencias.

### B. Unidad Systemd (`nanobanana-bot.service`)
Incluye directivas de seguridad para el servidor:
- `NoNewPrivileges=true`
- `ProtectSystem=full`
- `ProtectHome=read-only`
- `PrivateTmp=true`
- `Restart=always` con intervalo de reconexión

---

## 5. 🔐 Gestión de Secretos en el VPS

En el VPS, el archivo de variables reales debe residir en:
`/home/ganimedes/ganimedesmkt/nanobanana_bot/.env` con permisos restringidos:

```bash
chmod 600 /home/ganimedes/ganimedesmkt/nanobanana_bot/.env
```

Contenido necesario:
```ini
TELEGRAM_TOKEN=tu_token_de_telegram
OPENROUTER_API_KEY=tu_api_key_de_openrouter
MODEL_NAME=meta-llama/llama-3.2-11b-vision-instruct:free
```

---

## 6. 🚀 Ejecución y Comprobación en Producción

### Sincronización Manual vía SSH
```bash
# Conectarse al VPS
ssh ganimedesvps

# Ir al directorio del proyecto
cd /home/ganimedes/ganimedesmkt

# Crear/activar venv
python3 -m venv venv
source venv/bin/activate
pip install -r nanobanana_bot/requirements.txt
```

### Gestión del Servicio Systemd
```bash
# Ver estado del servicio
sudo systemctl status nanobanana-bot

# Ver logs en vivo
journalctl -u nanobanana-bot -f -n 100
```
