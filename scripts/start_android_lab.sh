#!/usr/bin/env bash
# start_android_lab.sh — arranca emulador y espera a que esté listo.
# NO abre scrcpy (usa open_scrcpy.sh para eso).
# No toca configuración global. Solo variables de entorno locales al script.

set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"
ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.config/.android/avd}"
EMULATOR_BIN="$ANDROID_HOME/emulator/emulator"
AVD_NAME="${1:-pixel_hermes_api36}"
SERIAL="emulator-5554"
TIMEOUT=120  # segundos máximo esperando boot

export ANDROID_HOME ANDROID_AVD_HOME

echo "[lab] Arrancando emulador: $AVD_NAME"

# Comprobar si ya hay un emulador corriendo
if adb -s "$SERIAL" get-state 2>/dev/null | grep -q "device"; then
    echo "[lab] El emulador $SERIAL ya está corriendo — nada que hacer."
    exit 0
fi

# Lanzar emulador headless con SwiftShader (seguro en NVIDIA/Wayland).
# NO se usa -wipe-data: borraría el Keystore y con él las API keys de PR 2.
# Para un borrado limpio puntual: avdmanager delete avd -n pixel_hermes_api36
"$EMULATOR_BIN" \
    -avd "$AVD_NAME" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -gpu swiftshader_indirect \
    &> /tmp/hermes-emulator.log &

EMULATOR_PID=$!
echo "[lab] Emulador PID: $EMULATOR_PID (log: /tmp/hermes-emulator.log)"

# Esperar a que adb detecte el dispositivo
echo -n "[lab] Esperando conexión adb"
ELAPSED=0
while ! adb -s "$SERIAL" get-state 2>/dev/null | grep -q "device"; do
    sleep 2; ELAPSED=$((ELAPSED + 2))
    echo -n "."
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo ""
        echo "[lab] ERROR: timeout esperando $SERIAL después de ${TIMEOUT}s"
        echo "[lab] Revisa /tmp/hermes-emulator.log"
        exit 1
    fi
done
echo ""

# Esperar a que el sistema Android haya completado el boot
echo -n "[lab] Esperando boot completo"
ELAPSED=0
while [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
    sleep 2; ELAPSED=$((ELAPSED + 2))
    echo -n "."
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo ""
        echo "[lab] ERROR: timeout esperando boot_completed"
        exit 1
    fi
done
echo ""

echo "[lab] Emulador listo: $SERIAL ($(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r'))"
echo "[lab] Ahora puedes ejecutar: scripts/open_scrcpy.sh"
