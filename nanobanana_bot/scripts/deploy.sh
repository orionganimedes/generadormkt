#!/usr/bin/env bash
# Despliegue de NanoBanana Bot en el VPS mediante SSH + systemd.
# Uso:
#   ./deploy.sh            # validación + despliegue real
#   ./deploy.sh --check    # solo preflight local, no contacta al VPS
#   ./deploy.sh --help

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

MODE="deploy"
case "${1:-}" in
    --check|--dry-run) MODE="check" ;;
    --help|-h)
        sed -n '2,6p' "$0"
        exit 0
        ;;
    "") ;;
    *)
        printf 'Opción no reconocida: %s (usa --check o --help)\n' "$1" >&2
        exit 2
        ;;
esac

# Archivos que deben existir y tener contenido antes de tocar el VPS.
REQUIRED_CODE_FILES=(
    "bot.py"
    "requirements.txt"
    "config/settings.py"
    "services/openrouter_service.py"
)

collect_local_issues() {
    local -a issues=()
    local f v

    for f in "${REQUIRED_CODE_FILES[@]}"; do
        [[ -s "${APP_ROOT}/${f}" ]] || issues+=("Código incompleto: ${f} está vacío (0 bytes)")
    done

    for v in VPS_HOST VPS_USER VPS_SSH_KEY VPS_PROJECT_PATH; do
        [[ -n "${!v:-}" ]] || issues+=("Variable no definida: ${v} (ver deploy/deploy.env.example)")
    done

    if [[ -n "${VPS_SSH_KEY:-}" && ! -r "${VPS_SSH_KEY}" ]]; then
        issues+=("La clave SSH no existe o no es legible: ${VPS_SSH_KEY}")
    fi

    if [[ -n "${VPS_PROJECT_PATH:-}" && "${VPS_PROJECT_PATH}" != /* ]]; then
        issues+=("VPS_PROJECT_PATH debe ser una ruta absoluta: ${VPS_PROJECT_PATH}")
    fi

    if [[ "${DEPLOY_METHOD}" != "git" && "${DEPLOY_METHOD}" != "rsync" ]]; then
        issues+=("DEPLOY_METHOD inválido: ${DEPLOY_METHOD} (usar 'git' o 'rsync')")
    fi

    if ((${#issues[@]} > 0)); then
        printf '\n%s[FAIL]%s Preflight local falló (%d problema(s)):\n' \
            "$C_RED" "$C_RESET" "${#issues[@]}" >&2
        for v in "${issues[@]}"; do
            printf '  - %s\n' "$v" >&2
        done
        printf '\nNo se contactó al VPS. Corrige lo anterior y reintenta.\n' >&2
        return 1
    fi
}

on_error() {
    local rc=$? line=$1
    set +e
    warn "Error inesperado (línea $line, código $rc)"
    if [[ "${CODE_SYNCED:-0}" == "1" && -z "${FINAL_STATE:-}" ]]; then
        warn "Intentando restaurar el servicio en el VPS"
        perform_rollback
        if [[ "${ROLLBACK_DONE:-0}" == "1" ]]; then FINAL_STATE="ROLLBACK"; else FINAL_STATE="FALLIDO"; fi
        HEALTHCHECK_RESULT="${HEALTHCHECK_RESULT:-NO EJECUTADO}"
        print_summary
    fi
    exit 1
}

perform_rollback() {
    ROLLBACK_DONE=0
    if [[ "$AUTO_ROLLBACK" != "1" ]]; then
        warn "AUTO_ROLLBACK=0: no se revierte automáticamente."
        return 0
    fi
    if [[ "$DEPLOY_METHOD" != "git" || -z "${PREV_COMMIT:-}" ]]; then
        warn "Sin commit previo (método $DEPLOY_METHOD): rollback manual requerido."
        return 0
    fi

    warn "Revirtiendo a ${PREV_COMMIT:0:12}"
    if ssh_exec "bash -s" <<EOF
set -euo pipefail
cd '$VPS_PROJECT_PATH'
git reset --hard '$PREV_COMMIT'
$SUDO_CMD systemctl restart '$SERVICE_NAME'
EOF
    then
        if remote_healthcheck; then
            ROLLBACK_DONE=1
            ok "Rollback verificado: el servicio quedó sano en ${PREV_COMMIT:0:12}"
        else
            warn "Rollback aplicado pero el healthcheck sigue fallando."
        fi
    else
        warn "El rollback falló; revisa el VPS manualmente."
    fi
}

main() {
    load_deploy_env

    VPS_PORT="${VPS_PORT:-22}"
    DEPLOY_METHOD="${DEPLOY_METHOD:-git}"
    GIT_BRANCH="${GIT_BRANCH:-main}"
    SERVICE_NAME="${SERVICE_NAME:-nanobanana-bot}"
    RUN_USER="${RUN_USER:-${VPS_USER:-}}"
    HEALTHCHECK_RETRIES="${HEALTHCHECK_RETRIES:-12}"
    HEALTHCHECK_INTERVAL="${HEALTHCHECK_INTERVAL:-5}"
    AUTO_ROLLBACK="${AUTO_ROLLBACK:-1}"
    TELEGRAM_HEALTHCHECK="${TELEGRAM_HEALTHCHECK:-1}"
    SUDO_CMD="${SUDO_CMD:-sudo}"
    ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

    log "Preflight local"
    collect_local_issues || exit 1
    ok "Código presente y variables obligatorias definidas"

    if [[ "$MODE" == "check" ]]; then
        printf '\nDestino:  %s@%s:%s (puerto %s)\n' \
            "$VPS_USER" "$VPS_HOST" "$VPS_PROJECT_PATH" "$VPS_PORT"
        printf 'Método:   %s | Rama: %s\n' "$DEPLOY_METHOD" "$GIT_BRANCH"
        printf 'Servicio: %s | Usuario del servicio: %s\n' "$SERVICE_NAME" "$RUN_USER"
        printf '\nPreflight OK. No se contactó al VPS (modo --check).\n'
        exit 0
    fi

    require_cmd ssh
    require_cmd rsync
    require_cmd flock
    if [[ "$DEPLOY_METHOD" == "git" ]]; then
        require_cmd git
    fi

    mkdir -p "${REPO_ROOT}/logs"
    LOG_FILE="${REPO_ROOT}/logs/deploy-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    trap 'on_error $LINENO' ERR

    exec 9>"${TMPDIR:-/tmp}/nanobanana-bot-deploy.lock"
    flock -n 9 || die "Ya hay otro despliegue en curso."

    if [[ "$DEPLOY_METHOD" == "git" ]]; then
        git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
            || die "El método git requiere que el proyecto local sea un repositorio git."
        if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
            if [[ "$ALLOW_DIRTY" == "1" ]]; then
                warn "Árbol de trabajo sucio; se desplegará lo publicado en origin/$GIT_BRANCH."
            else
                die "Árbol de trabajo sucio. Haz commit o usa ALLOW_DIRTY=1."
            fi
        fi
        LOCAL_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD)"
        LOCAL_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
        if [[ "$LOCAL_BRANCH" != "$GIT_BRANCH" ]]; then
            warn "Rama local '$LOCAL_BRANCH' != GIT_BRANCH '$GIT_BRANCH'; el VPS usará origin/$GIT_BRANCH."
        fi
        log "Commit local: $LOCAL_COMMIT ($LOCAL_BRANCH)"
    fi

    build_ssh_opts

    log "Verificando conexión SSH con $SSH_TARGET"
    ssh_exec "true" || die "No se pudo conectar por SSH a $SSH_TARGET"
    ok "SSH operativo"

    log "Comprobando el servidor (coordinación con VPSGanímedes)"
    ssh_exec "id -u '$RUN_USER' >/dev/null 2>&1" \
        || die "El usuario '$RUN_USER' no existe en el VPS."
    ssh_exec "command -v python3 >/dev/null 2>&1 && python3 -c 'import venv' 2>/dev/null" \
        || die "Falta python3 con soporte de venv en el VPS."
    ssh_exec "command -v git >/dev/null 2>&1" \
        || die "Falta git en el VPS."
    ssh_exec "command -v '$SUDO_CMD' >/dev/null 2>&1" \
        || die "No existe '$SUDO_CMD' en el VPS."
    ssh_exec "$SUDO_CMD -n true" \
        || die "El usuario '$VPS_USER' no puede usar '$SUDO_CMD' sin contraseña."

    RUN_GROUP="$(ssh_exec "id -gn '$RUN_USER'")"

    if [[ "$DEPLOY_METHOD" == "git" ]]; then
        ssh_exec "test -d '$VPS_PROJECT_PATH/.git'" \
            || die "No hay repositorio git en $VPS_PROJECT_PATH. Haz el bootstrap con DEPLOY_METHOD=rsync o clona el repo en el VPS."
    else
        ssh_exec "bash -s" <<EOF
set -euo pipefail
if [ ! -d '$VPS_PROJECT_PATH' ]; then
    $SUDO_CMD mkdir -p '$VPS_PROJECT_PATH'
    $SUDO_CMD chown '$RUN_USER':'$RUN_GROUP' '$VPS_PROJECT_PATH'
fi
EOF
    fi

    ENV_STATUS="$(ssh_exec "bash -s" <<EOF
set -uo pipefail
f='$VPS_PROJECT_PATH/nanobanana_bot/.env'
if [ ! -r "\$f" ]; then echo 'missing'; exit 0; fi
missing=''
grep -qE '^[[:space:]]*TELEGRAM_TOKEN[[:space:]]*=[[:space:]]*[^[:space:]]+' "\$f" || missing="\$missing TELEGRAM_TOKEN"
grep -qE '^[[:space:]]*OPENROUTER_API_KEY[[:space:]]*=[[:space:]]*[^[:space:]]+' "\$f" || missing="\$missing OPENROUTER_API_KEY"
echo "\${missing:-ok}"
EOF
)"
    if [[ "$ENV_STATUS" == "missing" ]]; then
        die "No existe $VPS_PROJECT_PATH/nanobanana_bot/.env en el VPS. Créalo con TELEGRAM_TOKEN y OPENROUTER_API_KEY."
    elif [[ "$ENV_STATUS" != "ok" ]]; then
        die "Faltan variables en el .env del VPS:$ENV_STATUS"
    fi
    ok ".env del VPS presente y completo"

    DISK_KB="$(ssh_exec "df -Pk '$VPS_PROJECT_PATH' | awk 'NR==2{print \$4}'" 2>/dev/null || echo 0)"
    MEM_KB="$(ssh_exec "awk '/MemAvailable/{print \$2}' /proc/meminfo" 2>/dev/null || echo 0)"
    LOAD1="$(ssh_exec "cut -d' ' -f1 /proc/loadavg" 2>/dev/null || echo '?')"
    if (( DISK_KB < 512000 )); then
        warn "Poco espacio libre en el VPS: $((DISK_KB / 1024)) MB"
    fi
    if (( MEM_KB < 262144 )); then
        warn "Memoria disponible baja en el VPS: $((MEM_KB / 1024)) MB"
    fi
    log "Servidor: carga $LOAD1 | disco libre $((DISK_KB / 1024)) MB | RAM disponible $((MEM_KB / 1024)) MB"

    PREV_COMMIT=""
    if [[ "$DEPLOY_METHOD" == "git" ]]; then
        PREV_COMMIT="$(ssh_exec "git -C '$VPS_PROJECT_PATH' rev-parse HEAD 2>/dev/null || true")"
        log "Commit actual en el VPS: ${PREV_COMMIT:0:12}"
    fi

    log "Sincronizando código (método: $DEPLOY_METHOD)"
    if [[ "$DEPLOY_METHOD" == "git" ]]; then
        ssh_exec "bash -s" <<EOF
set -euo pipefail
cd '$VPS_PROJECT_PATH'
git fetch --prune origin
git checkout -f '$GIT_BRANCH'
git reset --hard 'origin/$GIT_BRANCH'
EOF
        DEPLOYED_VERSION="$(ssh_exec "git -C '$VPS_PROJECT_PATH' rev-parse --short=12 HEAD")"
    else
        rsync -az --delete \
            --exclude '.git/' \
            --exclude 'venv/' \
            --exclude '.venv/' \
            --exclude '__pycache__/' \
            --exclude '.env' \
            --exclude 'logs/' \
            -e "ssh ${SSH_OPTS[*]}" \
            "${REPO_ROOT}/" "${SSH_TARGET}:${VPS_PROJECT_PATH}/"
        DEPLOYED_VERSION="rsync-$(date +%Y%m%d-%H%M%S)"
    fi
    CODE_SYNCED=1
    ok "Código sincronizado: $DEPLOYED_VERSION"

    log "Instalando dependencias en el VPS"
    ssh_exec "bash -s" <<EOF
set -euo pipefail
cd '$VPS_PROJECT_PATH'
if [ ! -x venv/bin/python ]; then
    python3 -m venv venv
fi
./venv/bin/python -m pip install --upgrade pip wheel --quiet
./venv/bin/python -m pip install --no-cache-dir -r nanobanana_bot/requirements.txt
./venv/bin/python -c 'import telegram, requests, dotenv'
EOF
    ok "Dependencias instaladas y verificadas"

    log "Instalando unidad systemd"
    UNIT_TMP="$(mktemp)"
    sed -e "s|@PROJECT_PATH@|${VPS_PROJECT_PATH}|g" \
        -e "s|@RUN_USER@|${RUN_USER}|g" \
        -e "s|@RUN_GROUP@|${RUN_GROUP}|g" \
        "${APP_ROOT}/deploy/systemd/nanobanana-bot.service" > "$UNIT_TMP"
    scp "${SCP_OPTS[@]}" "$UNIT_TMP" "${SSH_TARGET}:/tmp/${SERVICE_NAME}.service" >/dev/null
    rm -f "$UNIT_TMP"
    ssh_exec "bash -s" <<EOF
set -euo pipefail
$SUDO_CMD install -m 0644 '/tmp/$SERVICE_NAME.service' '/etc/systemd/system/$SERVICE_NAME.service'
rm -f '/tmp/$SERVICE_NAME.service'
$SUDO_CMD systemctl daemon-reload
$SUDO_CMD systemctl enable '$SERVICE_NAME' >/dev/null
$SUDO_CMD systemctl restart '$SERVICE_NAME'
EOF
    ok "Servicio $SERVICE_NAME reiniciado"

    log "Healthcheck (hasta $HEALTHCHECK_RETRIES intentos cada ${HEALTHCHECK_INTERVAL}s)"
    HEALTH_OK=0
    for ((attempt = 1; attempt <= HEALTHCHECK_RETRIES; attempt++)); do
        if remote_healthcheck; then
            HEALTH_OK=1
            break
        fi
        warn "Intento $attempt/$HEALTHCHECK_RETRIES fallido; esperando ${HEALTHCHECK_INTERVAL}s"
        sleep "$HEALTHCHECK_INTERVAL"
    done

    if ((HEALTH_OK == 1)); then
        HEALTHCHECK_RESULT="PASÓ"
        FINAL_STATE="EXITOSO"
        ok "Despliegue exitoso"
    else
        HEALTHCHECK_RESULT="FALLÓ"
        warn "Healthcheck falló tras el despliegue"
        perform_rollback
        if [[ "${ROLLBACK_DONE:-0}" == "1" ]]; then
            FINAL_STATE="ROLLBACK"
        else
            FINAL_STATE="FALLIDO"
        fi
    fi

    print_summary
    [[ "$FINAL_STATE" == "EXITOSO" ]] || exit 1
}

main "$@"
