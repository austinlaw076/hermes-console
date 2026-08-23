#!/usr/bin/env bash
# restart_android_lab.sh — fuerza cierre completo y reinicia el entorno.
# Usar cuando el emulador o adb están colgados y no responden.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[lab] Reinicio completo del entorno..."

# Cierre forzado de todo.
# Se usa el patrón del AVD para no matar emuladores de otros proyectos.
pkill -KILL -x scrcpy 2>/dev/null || true
pkill -KILL -f "emulator.*pixel_hermes_api36" 2>/dev/null || true
pkill -KILL -f "qemu-system.*pixel_hermes_api36" 2>/dev/null || true
sleep 2

# Reiniciar servidor adb — esto resuelve la mayoría de estados inconsistentes
echo "[lab] Reiniciando servidor adb..."
adb kill-server 2>/dev/null || true
sleep 1
adb start-server
sleep 2

echo "[lab] Procesos limpiados. Iniciando emulador..."
"$SCRIPT_DIR/start_android_lab.sh"
