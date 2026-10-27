#!/usr/bin/env bash
# Healthcheck de NanoBanana Bot. Se ejecuta EN el VPS a través de SSH:
#   PROJECT_PATH=/opt/nanobanana_bot SERVICE_NAME=nanobanana-bot bash healthcheck.sh
# No requiere puertos abiertos: el bot usa long polling saliente contra Telegram.

set -uo pipefail

PROJECT_PATH="${PROJECT_PATH:-/opt/nanobanana_bot}"
SERVICE_NAME="${SERVICE_NAME:-nanobanana-bot}"
SUDO_CMD="${SUDO_CMD:-sudo}"
TELEGRAM_HEALTHCHECK="${TELEGRAM_HEALTHCHECK:-1}"
ENV_FILE="${PROJECT_PATH}/nanobanana_bot/.env"

FAILED=()

pass() { printf '  [ok]   %s\n' "$1"; }
fail() { printf '  [fail] %s\n' "$1"; FAILED+=("$1"); }
skip() { printf '  [skip] %s\n' "$1"; }

printf 'Healthcheck: %s (%s)\n' "$SERVICE_NAME" "$PROJECT_PATH"

# 1. Servicio activo en systemd
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    pass "systemd: servicio activo"
else
    fail "systemd: servicio inactivo"
fi

# 2. Proceso principal correcto y estable
MAIN_PID="$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || true)"
MAIN_PID="${MAIN_PID:-0}"
if [[ "$MAIN_PID" =~ ^[0-9]+$ ]] && (( MAIN_PID > 0 )) && kill -0 "$MAIN_PID" 2>/dev/null; then
    pass "proceso vivo (PID $MAIN_PID)"
    CMDLINE="$(tr '\0' ' ' < "/proc/${MAIN_PID}/cmdline" 2>/dev/null || true)"
    if [[ "$CMDLINE" == *"nanobanana_bot.bot"* ]]; then
        pass "comando esperado: python -m nanobanana_bot.bot"
    else
        fail "comando inesperado: ${CMDLINE:-desconocido}"
    fi
    ETIMES="$(ps -o etimes= -p "$MAIN_PID" 2>/dev/null | tr -d ' ')"
    if [[ "$ETIMES" =~ ^[0-9]+$ ]] && (( ETIMES >= 10 )); then
        pass "proceso estable (${ETIMES}s en ejecución)"
    else
        fail "proceso inestable (posible bucle de reinicio)"
    fi
else
    fail "no hay proceso principal (MainPID=${MAIN_PID:-?})"
fi

# 3. Journal reciente sin errores fatales
JOURNAL=(journalctl -u "$SERVICE_NAME" --since "-3 min" --no-pager -q)
if ! "${JOURNAL[@]}" -n 0 >/dev/null 2>&1 && [[ -n "$SUDO_CMD" ]]; then
    JOURNAL=("$SUDO_CMD" "${JOURNAL[@]}")
fi
RECENT_LOGS="$("${JOURNAL[@]}" 2>/dev/null | tail -n 200 || true)"
if [[ -n "$RECENT_LOGS" ]] && grep -Eqi 'traceback|CRITICAL|Conflict: terminated by other getUpdates|InvalidToken|Unauthorized' <<< "$RECENT_LOGS"; then
    fail "journal: errores fatales recientes"
    grep -Ei 'traceback|CRITICAL|Conflict: terminated by other getUpdates|InvalidToken|Unauthorized' <<< "$RECENT_LOGS" \
        | tail -n 5 | sed 's/^/         /'
else
    pass "journal: sin errores fatales en los últimos 3 min"
fi

# 4. Variables de entorno de la aplicación
if [[ -r "$ENV_FILE" ]]; then
    pass "archivo .env presente"
    PERMS="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)"
    if [[ "$PERMS" == "600" || "$PERMS" == "640" ]]; then
        pass ".env con permisos $PERMS"
    else
        fail ".env con permisos ${PERMS:-desconocidos} (se esperaba 600)"
    fi
    if grep -qE '^[[:space:]]*TELEGRAM_TOKEN[[:space:]]*=[[:space:]]*[^[:space:]]+' "$ENV_FILE"; then
        pass "TELEGRAM_TOKEN definido"
    else
        fail "TELEGRAM_TOKEN ausente o vacío"
    fi
    if grep -qE '^[[:space:]]*OPENROUTER_API_KEY[[:space:]]*=[[:space:]]*[^[:space:]]+' "$ENV_FILE"; then
        pass "OPENROUTER_API_KEY definida"
    else
        fail "OPENROUTER_API_KEY ausente o vacía"
    fi
else
    fail "no se puede leer $ENV_FILE"
fi

# 5. Verificación real contra la API de Telegram (sin exponer el token)
if [[ "$TELEGRAM_HEALTHCHECK" == "1" && -r "$ENV_FILE" ]]; then
    TOKEN="$(sed -n 's/^[[:space:]]*TELEGRAM_TOKEN[[:space:]]*=[[:space:]]*//p' "$ENV_FILE" \
        | tail -n 1 | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
    if [[ -z "$TOKEN" ]]; then
        fail "Telegram API: no hay token para verificar"
    elif command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 10 "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null | grep -q '"ok":true'; then
            pass "Telegram API: getMe OK"
        else
            fail "Telegram API: getMe falló (token inválido o sin red)"
        fi
    else
        skip "Telegram API: curl no disponible en el VPS"
    fi
fi

# 6. Espacio en disco
AVAIL_KB="$(df -Pk "$PROJECT_PATH" 2>/dev/null | awk 'NR==2{print $4}')"
if [[ "$AVAIL_KB" =~ ^[0-9]+$ ]] && (( AVAIL_KB > 204800 )); then
    pass "disco: $((AVAIL_KB / 1024)) MB libres"
else
    fail "disco: espacio insuficiente (${AVAIL_KB:-?} KB)"
fi

printf '\n'
if ((${#FAILED[@]} > 0)); then
    printf 'Healthcheck FALLÓ (%d problema(s))\n' "${#FAILED[@]}"
    exit 1
fi
printf 'Healthcheck OK\n'
