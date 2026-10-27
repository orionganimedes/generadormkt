#!/usr/bin/env bash
# Rollback manual de NanoBanana Bot a un commit o tag concreto.
# Uso: ./rollback.sh <commit|tag>   (o ROLLBACK_TO=<commit|tag> ./rollback.sh)

set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

main() {
    load_deploy_env

    VPS_PORT="${VPS_PORT:-22}"
    SERVICE_NAME="${SERVICE_NAME:-nanobanana-bot}"
    TELEGRAM_HEALTHCHECK="${TELEGRAM_HEALTHCHECK:-1}"
    SUDO_CMD="${SUDO_CMD:-sudo}"

    local target="${1:-${ROLLBACK_TO:-}}"
    [[ -n "$target" ]] || die "Uso: rollback.sh <commit|tag> (o define ROLLBACK_TO)"
    [[ "$target" =~ ^[A-Za-z0-9._/-]+$ ]] || die "Referencia inválida: $target"

    local v
    for v in VPS_HOST VPS_USER VPS_SSH_KEY VPS_PROJECT_PATH; do
        [[ -n "${!v:-}" ]] || die "Variable no definida: $v"
    done

    require_cmd ssh
    build_ssh_opts

    log "Verificando que $target existe en $VPS_PROJECT_PATH"
    ssh_exec "git -C '$VPS_PROJECT_PATH' cat-file -e '${target}^{commit}'" \
        || die "La referencia '$target' no existe en el repositorio del VPS."

    ssh_exec "bash -s" <<EOF
set -euo pipefail
cd '$VPS_PROJECT_PATH'
git reset --hard '$target'
$SUDO_CMD systemctl restart '$SERVICE_NAME'
EOF
    ok "Código revertido a $target y servicio reiniciado"

    if remote_healthcheck; then
        ok "Healthcheck posterior al rollback: PASÓ"
        FINAL_STATE="ROLLBACK"
    else
        warn "Healthcheck posterior al rollback: FALLÓ"
        FINAL_STATE="FALLIDO"
    fi

    DEPLOYED_VERSION="$target"
    HEALTHCHECK_RESULT="$([[ "$FINAL_STATE" == "ROLLBACK" ]] && echo 'PASÓ' || echo 'FALLÓ')"
    print_summary
    [[ "$FINAL_STATE" == "ROLLBACK" ]] || exit 1
}

main "$@"
