#!/usr/bin/env bash
# stop_android_lab.sh — cierra scrcpy y el emulador de forma limpia.
# Primero intenta cierre graceful (adb emu kill), luego SIGTERM, finalmente SIGKILL.

set -uo pipefail

SERIAL="${1:-emulator-5554}"

echo "[lab] Cerrando entorno de laboratorio..."

# 1. Cerrar scrcpy si está corriendo
if pgrep -x scrcpy > /dev/null 2>&1; then
    echo "[lab] Cerrando scrcpy..."
    pkill -x scrcpy
    sleep 1
fi

# 2. Cerrar el emulador — vía adb si está accesible
if adb -s "$SERIAL" get-state 2>/dev/null | grep -q "device"; then
    echo "[lab] Cerrando emulador via adb emu kill..."
    adb -s "$SERIAL" emu kill 2>/dev/null || true
    sleep 3
fi

# 3. Si el proceso del emulador sigue vivo, SIGTERM
if pgrep -f "emulator.*pixel_hermes_api36" > /dev/null 2>&1; then
    echo "[lab] Emulador sigue vivo — enviando SIGTERM..."
    pkill -TERM -f "emulator.*pixel_hermes_api36" || true
    sleep 3
fi

# 4. Si todavía sigue, SIGKILL
if pgrep -f "emulator.*pixel_hermes_api36" > /dev/null 2>&1; then
    echo "[lab] Emulador no respondió — SIGKILL..."
    pkill -KILL -f "emulator.*pixel_hermes_api36" || true
    sleep 1
fi

# 5. Verificar que no queda nada
LEFTOVER=""
pgrep -x scrcpy > /dev/null 2>&1 && LEFTOVER="$LEFTOVER scrcpy"
pgrep -f "emulator.*pixel_hermes_api36" > /dev/null 2>&1 && LEFTOVER="$LEFTOVER emulator"

if [ -n "$LEFTOVER" ]; then
    echo "[lab] AVISO: todavía hay procesos vivos:$LEFTOVER"
    echo "[lab] Usa 'scripts/restart_android_lab.sh' si el entorno está colgado."
    exit 1
fi

echo "[lab] Entorno cerrado limpiamente."
