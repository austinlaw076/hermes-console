#!/usr/bin/env bash
# dev.sh — flujo completo de desarrollo: build(opcional) → install → launch → scrcpy interactivo
#
# Uso:
#   scripts/dev.sh              → instala APK existente, lanza app, abre scrcpy
#   scripts/dev.sh --build      → compila primero, luego instala, lanza y abre scrcpy
#   scripts/dev.sh --build --no-scrcpy  → compila, instala y lanza sin abrir ventana
#
# Equivale a correr en secuencia:
#   scripts/install_debug_apk.sh [--build]
#   argent run launch-app ...
#   scripts/open_scrcpy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
APK="$REPO_DIR/build/app/outputs/flutter-apk/app-debug.apk"
SERIAL="${SERIAL:-emulator-5554}"
BUNDLE_ID="com.hermesagent.hermes_android"
ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"
ANDROID_SDK_ROOT="$ANDROID_HOME"
FLUTTER="${FLUTTER:-$HOME/.local/share/flutter-sdk/flutter/bin/flutter}"

export ANDROID_HOME ANDROID_SDK_ROOT

BUILD=false
OPEN_SCRCPY=true

for arg in "$@"; do
    case "$arg" in
        --build)      BUILD=true ;;
        --no-scrcpy)  OPEN_SCRCPY=false ;;
    esac
done

# ── 0. Verificar emulador ────────────────────────────────────────────────────
if ! adb -s "$SERIAL" get-state 2>/dev/null | grep -q "device"; then
    echo "[dev] Emulador $SERIAL no detectado — arrancando lab..."
    "$SCRIPT_DIR/start_android_lab.sh"
fi

# ── 1. Build (opcional) ──────────────────────────────────────────────────────
if $BUILD; then
    echo "[dev] Compilando APK debug..."
    cd "$REPO_DIR"
    "$FLUTTER" build apk --debug
fi

if [ ! -f "$APK" ]; then
    echo "[dev] ERROR: APK no encontrada en $APK"
    echo "[dev] Ejecuta con --build para compilar primero."
    exit 1
fi

# ── 2. Instalar ───────────────────────────────────────────────────────────────
APK_SIZE=$(du -sh "$APK" | cut -f1)
echo "[dev] Instalando $APK ($APK_SIZE) en $SERIAL..."
adb -s "$SERIAL" install -r "$APK"
echo "[dev] Instalado."

# ── 3. Lanzar app ─────────────────────────────────────────────────────────────
echo "[dev] Lanzando $BUNDLE_ID en $SERIAL..."
adb -s "$SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 \
    > /dev/null 2>&1 \
    || adb -s "$SERIAL" shell am start \
        -n "${BUNDLE_ID}/${BUNDLE_ID}.MainActivity" \
        > /dev/null 2>&1 \
    || true

sleep 1
echo "[dev] App lanzada."

# ── 4. Abrir scrcpy interactivo ───────────────────────────────────────────────
if $OPEN_SCRCPY; then
    echo "[dev] Abriendo scrcpy interactivo..."
    "$SCRIPT_DIR/open_scrcpy.sh"
    echo "[dev] Listo — interactúa con la app en la ventana de scrcpy."
    echo "[dev] Controles: click=tap · arrastrar=swipe · Ctrl+H=Home · Ctrl+Z=Atrás"
else
    echo "[dev] scrcpy omitido (--no-scrcpy)."
    echo "[dev] Para abrir después: scripts/open_scrcpy.sh"
fi
