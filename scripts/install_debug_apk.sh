#!/usr/bin/env bash
# install_debug_apk.sh — compila (opcional) e instala el APK debug en el emulador.
# Uso:
#   scripts/install_debug_apk.sh           → solo instala APK existente
#   scripts/install_debug_apk.sh --build   → compila y luego instala

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
APK="$REPO_DIR/build/app/outputs/flutter-apk/app-debug.apk"
SERIAL="${SERIAL:-emulator-5554}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"
ANDROID_SDK_ROOT="$ANDROID_HOME"
FLUTTER="${FLUTTER:-$HOME/.local/share/flutter-sdk/flutter/bin/flutter}"

export ANDROID_HOME ANDROID_SDK_ROOT

BUILD=false
for arg in "$@"; do
    [ "$arg" = "--build" ] && BUILD=true
done

# Verificar que el emulador está listo
if ! adb -s "$SERIAL" get-state 2>/dev/null | grep -q "device"; then
    echo "[install] ERROR: $SERIAL no disponible. Ejecuta start_android_lab.sh primero."
    exit 1
fi

if $BUILD; then
    echo "[install] Compilando APK debug..."
    cd "$REPO_DIR"
    "$FLUTTER" build apk --debug
fi

if [ ! -f "$APK" ]; then
    echo "[install] ERROR: APK no encontrada en $APK"
    echo "[install] Ejecuta con --build o compila primero con: flutter build apk --debug"
    exit 1
fi

APK_SIZE=$(du -sh "$APK" | cut -f1)
echo "[install] Instalando $APK ($APK_SIZE) en $SERIAL..."

adb -s "$SERIAL" install -r "$APK"

echo "[install] Instalado. Para lanzar la app:"
echo "[install]   argent run launch-app --udid $SERIAL --bundleId com.hermesagent.hermes_android"
