#!/usr/bin/env bash
# qa-apply.sh — Download QA APK from GitHub and install on local emulator.
# Usage:
#   ./scripts/qa-apply.sh              # Download latest QA artifact + install
#   ./scripts/qa-apply.sh --build-only # Build only, no install
#   ./scripts/qa-apply.sh --skip-build # Skip build, just download+install
#
# The GitHub Actions artifact must be uploaded first. This script downloads
# the artifact URL from the Actions API and installs via adb.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
REPO="austinlaw076/hermes-console"
EMULATOR_SERIAL="${SERIAL:-emulator-5554}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[qa-apply]${NC} $1"; }
warn()  { echo -e "${YELLOW}[qa-apply]${NC} $1"; }
error() { echo -e "${RED}[qa-apply]${NC} $1"; exit 1; }

# Check if adb and emulator are available
check_emulator() {
  if ! adb -s "$EMULATOR_SERIAL" get-state 2>/dev/null | grep -q "device"; then
    warn "Emulator $EMULATOR_SERIAL not running. Starting..."
    "$SCRIPT_DIR/start_android_lab.sh" || error "Failed to start emulator"
  fi
}

# Download QA APK from GitHub Actions artifact
download_qa_apk() {
  local artifact_url
  info "Finding latest QA artifact from $REPO..."

  # Get the latest successful run's artifact download URL
  artifact_url=$(gh api "repos/$REPO/actions/artifacts" \
    --jq '.artifacts[] | select(.name=="hermes-qa-apk") | select(.expired==false) | .archive_download_url' \
    --jq '.[0]' 2>/dev/null) || error "Failed to fetch artifacts from GitHub"

  if [ -z "$artifact_url" ]; then
    error "No QA artifact found. Run the QA build workflow first."
  fi

  info "Downloading QA APK from artifact..."
  local output_dir="$REPO_DIR/build/app/outputs/flutter-apk"
  mkdir -p "$output_dir"

  # Download the zip artifact and extract the APK
  local zip_file="$output_dir/qa-artifact.zip"
  gh api "$artifact_url" --output "$zip_file" || error "Download failed"

  unzip -o "$zip_file" -d "$output_dir" > /dev/null 2>&1 || error "Failed to extract artifact"
  rm -f "$zip_file"

  info "QA APK downloaded successfully."
}

# Build QA APK locally
build_qa_apk() {
  info "Building QA APK locally..."
  cd "$REPO_DIR"
  flutter build apk --debug --flavor qa || error "Build failed"
  info "Build complete."
}

# Install QA APK on emulator
install_qa_apk() {
  check_emulator

  local apk_path="$REPO_DIR/build/app/outputs/flutter-apk/app-qa-debug.apk"
  if [ ! -f "$apk_path" ]; then
    error "QA APK not found at $apk_path"
  fi

  local apk_size=$(du -sh "$apk_path" | cut -f1)
  info "Installing QA APK ($apk_size) on $EMULATOR_SERIAL..."

  adb -s "$EMULATOR_SERIAL" install -r "$apk_path" || error "Install failed"

  info "✅ QA APK installed on $EMULATOR_SERIAL"
  echo ""
  echo "To launch: adb -s $EMULATOR_SERIAL shell am start -n com.hermesagent.hermes_android.qa/.MainActivity"
}

# Parse arguments
BUILD_ONLY=false
SKIP_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=true ; build_qa_apk ; exit 0 ;;
    --skip-build) SKIP_BUILD=true ;;
  esac
done

# Main flow
if $SKIP_BUILD; then
  download_qa_apk
else
  # Try to build first if APK doesn't exist or is older than 1 hour
  local_apk="$REPO_DIR/build/app/outputs/flutter-apk/app-qa-debug.apk"
  if [ ! -f "$local_apk" ] || [ $(find "$local_apk" -mmin +60 2>/dev/null | wc -l) -gt 0 ]; then
    build_qa_apk
  else
    info "Local APK found and recent, skipping build. Use --build-only to rebuild."
  fi
fi

check_emulator
install_qa_apk
