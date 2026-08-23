#!/usr/bin/env bash
# open_scrcpy.sh — abre una ventana interactiva del emulador.
# Requiere que el emulador esté corriendo (usa start_android_lab.sh primero).
#
# Uso:
#   scripts/open_scrcpy.sh              → interactivo (click/swipe en la ventana)
#   scripts/open_scrcpy.sh --view-only  → solo observación (sin control táctil)
#
# Controles en modo interactivo:
#   Click izquierdo = tap | Arrastrar = swipe | Scroll = scroll
#   Ctrl+H = Home | Ctrl+Z = Atrás | Ctrl+A = Recientes

set -euo pipefail

# Asegura que scrcpy pueda abrir ventana aunque el terminal no herede el entorno gráfico
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    # Intenta detectar la sesión gráfica del usuario activo
    _USER="${USER:-$(id -un)}"
    _DBUS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$(pgrep -u "$_USER" -n)/environ 2>/dev/null | tr -d '\0' | cut -d= -f2-) || true
    [ -n "$_DBUS" ] && export DBUS_SESSION_BUS_ADDRESS="$_DBUS"
    # Fallback a valores conocidos de Wayland/X11
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
    export DISPLAY="${DISPLAY:-:0}"
fi

SERIAL="emulator-5554"
WIDTH="390"
HEIGHT="844"
VIEW_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --view-only) VIEW_ONLY=true ;;
        emulator-*) SERIAL="$arg" ;;
        [0-9]*x[0-9]*) WIDTH="${arg%x*}"; HEIGHT="${arg#*x}" ;;
    esac
done

# Verificar que el emulador está disponible
if ! adb -s "$SERIAL" get-state 2>/dev/null | grep -q "device"; then
    echo "[scrcpy] ERROR: $SERIAL no está disponible. Ejecuta start_android_lab.sh primero."
    exit 1
fi

# Cerrar instancia anterior si existe
if pgrep -x scrcpy > /dev/null 2>&1; then
    echo "[scrcpy] Cerrando instancia anterior de scrcpy..."
    pkill -x scrcpy
    sleep 1
fi

if $VIEW_ONLY; then
    TITLE="Hermes Android · Lab (solo vista)"
    EXTRA_FLAGS="--no-control"
    echo "[scrcpy] Modo solo-vista — sin control táctil por la ventana."
else
    TITLE="Hermes Android · Lab"
    EXTRA_FLAGS=""
    echo "[scrcpy] Modo interactivo — click/swipe en la ventana para controlar el emulador."
fi

echo "[scrcpy] Abriendo ventana ${WIDTH}x${HEIGHT} para $SERIAL..."

# shellcheck disable=SC2086
scrcpy \
    -s "$SERIAL" \
    --window-title "$TITLE" \
    --window-width "$WIDTH" \
    --window-height "$HEIGHT" \
    --always-on-top \
    --no-audio \
    --video-codec=h264 \
    $EXTRA_FLAGS \
    &

SCRCPY_PID=$!
disown "$SCRCPY_PID"   # desvincula del shell — sobrevive al cierre del terminal

echo "[scrcpy] PID: $SCRCPY_PID — ventana abierta."
echo "[scrcpy] Para cerrar: pkill scrcpy   (o ejecuta stop_android_lab.sh)"
