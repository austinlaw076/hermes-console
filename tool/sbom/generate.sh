#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if [[ ! -f .dart_tool/package_config.json ]]; then
  flutter pub get
fi

python3 tool/sbom/generate.py --variant playRelease "$@"
python3 tool/sbom/generate.py --variant fullRelease "$@"

