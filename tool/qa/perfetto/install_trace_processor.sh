#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: install_trace_processor.sh [--verify-only]' \
    '' \
    'Descarga el prebuilt oficial fijado en trace_processor.lock dentro de' \
    'tool/qa/perfetto/.tools. Nunca escribe en HOME ni modifica PATH.' \
    '--verify-only no usa red y exige que el binario local ya exista.'
}

verify_only=0
while (($# > 0)); do
  case "$1" in
    --verify-only)
      verify_only=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      perfetto_die "argumento desconocido: $1"
      ;;
  esac
done

perfetto_validate_trace_processor_lock
release="$(perfetto_trace_processor_lock_value release)"
release_commit="$(perfetto_trace_processor_lock_value release_commit)"
artifact_platform="$(
  perfetto_trace_processor_lock_value artifact_platform
)"
artifact_file="$(perfetto_trace_processor_lock_value artifact_file)"
artifact_url="$(perfetto_trace_processor_lock_value artifact_url)"
expected_size="$(
  perfetto_trace_processor_lock_value artifact_size_bytes
)"
expected_sha256="$(
  perfetto_trace_processor_lock_value artifact_sha256
)"

[[ "$(uname -s)" == 'Linux' && "$(uname -m)" == 'x86_64' ]] ||
  perfetto_die 'host no compatible con el prebuilt linux-amd64 fijado'

readonly tools_dir="${SCRIPT_DIR}/.tools"
readonly target="${tools_dir}/${artifact_file}"
[[ ! -L "$tools_dir" ]] || perfetto_die ".tools no puede ser symlink: ${tools_dir}"
if ((verify_only == 1)); then
  [[ -d "$tools_dir" ]] ||
    perfetto_die "directorio de herramientas no instalado: ${tools_dir}"
else
  mkdir -p -- "$tools_dir"
fi
[[ -d "$tools_dir" && ! -L "$tools_dir" ]] ||
  perfetto_die ".tools no es un directorio fisico: ${tools_dir}"

verify_target() {
  local candidate="$1"
  [[ -f "$candidate" && ! -L "$candidate" ]] || return 1
  local actual_size
  local actual_sha256
  actual_size="$(stat -c '%s' -- "$candidate")"
  actual_sha256="$(sha256sum "$candidate" | awk '{print $1}')"
  [[ "$actual_size" == "$expected_size" &&
     "$actual_sha256" == "$expected_sha256" ]]
}

if [[ -L "$target" ]]; then
  perfetto_die "el target no puede ser symlink: ${target}"
elif [[ -e "$target" ]]; then
  verify_target "$target" ||
    perfetto_die "binario local existe pero no coincide con el lock: ${target}"
  if ((verify_only == 1)); then
    [[ -x "$target" ]] ||
      perfetto_die "binario fijado no es ejecutable: ${target}"
  else
    [[ -x "$target" ]] || chmod 0755 -- "$target"
  fi
elif ((verify_only == 1)); then
  perfetto_die "binario fijado no instalado: ${target}"
else
  command -v curl >/dev/null 2>&1 || perfetto_die 'curl no esta disponible'
  partial="$(mktemp "${tools_dir}/.${artifact_file}.partial.XXXXXX")"
  printf 'Descargando %s desde el artefacto oficial...\n' "$release"
  [[ -f "$partial" && ! -L "$partial" ]] ||
    perfetto_die "mktemp no creo un fichero regular: ${partial}"
  curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 20 --max-time 300 --max-filesize "$expected_size" \
    --output "$partial" "$artifact_url"
  if ! verify_target "$partial"; then
    perfetto_die \
      "descarga no coincide con size/SHA fijados; se conserva para diagnostico: ${partial}"
  fi
  chmod 0755 -- "$partial"
  [[ ! -e "$target" && ! -L "$target" ]] ||
    perfetto_die "el destino aparecio durante la descarga: ${target}"
  mv --no-clobber -- "$partial" "$target"
  [[ ! -e "$partial" ]] ||
    perfetto_die "publicacion atomica rechazada; se conserva: ${partial}"
fi

validated_target="$(perfetto_validate_trace_processor "$target")"
validated_version="$("$validated_target" --version)"
validated_version="${validated_version%%$'\n'*}"

printf '%s\n' \
  "trace_processor_release=${release}" \
  "trace_processor_commit=${release_commit}" \
  "trace_processor_version=${validated_version}" \
  "trace_processor_path=${validated_target}" \
  "trace_processor_size_bytes=${expected_size}" \
  "trace_processor_sha256=${expected_sha256}" \
  "trace_processor_origin=${artifact_url}"
