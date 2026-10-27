#!/usr/bin/env bash
# Utilidades compartidas por los scripts de despliegue de NanoBanana Bot.
# Se carga con `source`; no se ejecuta directamente.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
APP_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
readonly APP_ROOT
REPO_ROOT="$(cd -- "${APP_ROOT}/.." && pwd -P)"
readonly REPO_ROOT

if [[ -t 1 ]]; then
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_RESET=$'\033[0m'
else
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_RESET=''
fi
readonly C_RED C_GREEN C_YELLOW C_BLUE C_RESET

log()  { printf '%s[%s]%s %s\n' "$C_BLUE" "$(date +%H:%M:%S)" "$C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

load_deploy_env() {
    local file="${DEPLOY_ENV_FILE:-${APP_ROOT}/deploy/deploy.env}"
    if [[ -f "$file" ]]; then
        log "Cargando configuración: $file"
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a
    else
        warn "No existe $file; se usarán solo las variables del entorno."
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Falta el comando '$1' en el host local."
}

build_ssh_opts() {
    local port="${VPS_PORT:-22}"
    SSH_TARGET="${VPS_USER}@${VPS_HOST}"
    SSH_OPTS=(
        -o BatchMode=yes
        -o ConnectTimeout=15
        -o ServerAliveInterval=15
        -o StrictHostKeyChecking=accept-new
        -p "$port"
    )
    SCP_OPTS=(
        -o BatchMode=yes
        -o ConnectTimeout=15
        -o StrictHostKeyChecking=accept-new
        -P "$port"
    )
    if [[ -n "${VPS_SSH_KEY:-}" ]]; then
        SSH_OPTS+=(-i "$VPS_SSH_KEY" -o IdentitiesOnly=yes)
        SCP_OPTS+=(-i "$VPS_SSH_KEY" -o IdentitiesOnly=yes)
    fi
}

ssh_exec() { ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"; }

# Ejecuta healthcheck.sh en el VPS con las variables del despliegue.
remote_healthcheck() {
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
        "PROJECT_PATH=$(printf '%q' "${VPS_PROJECT_PATH}") \
SERVICE_NAME=$(printf '%q' "${SERVICE_NAME}") \
SUDO_CMD=$(printf '%q' "${SUDO_CMD}") \
TELEGRAM_HEALTHCHECK=$(printf '%q' "${TELEGRAM_HEALTHCHECK}") \
bash -s" < "${SCRIPT_DIR}/healthcheck.sh"
}

print_summary() {
    printf '\n%s===== RESUMEN DEL DESPLIEGUE =====%s\n' "$C_BLUE" "$C_RESET"
    printf '  Estado:       %s\n' "${FINAL_STATE:-DESCONOCIDO}"
    printf '  Versión:      %s\n' "${DEPLOYED_VERSION:-N/A}"
    printf '  VPS:          %s\n' "${SSH_TARGET:-N/A}"
    printf '  Ruta remota:  %s\n' "${VPS_PROJECT_PATH:-N/A}"
    printf '  Servicio:     %s\n' "${SERVICE_NAME:-N/A}"
    printf '  Healthcheck:  %s\n' "${HEALTHCHECK_RESULT:-NO EJECUTADO}"
    printf '  Log local:    %s\n' "${LOG_FILE:-N/A}"
    printf '%s==================================%s\n' "$C_BLUE" "$C_RESET"
}
