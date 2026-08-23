#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: verify_trace.sh --trace TRACE.pftrace --metadata metadata.txt' \
    '                       [--trace-processor RUTA]' \
    '' \
    'Exit 0: hay hermes.voice.turn y puntos suficientes.' \
    'Exit 1: traza invalida, consulta fallida o eventos Hermes ausentes.' \
    'Exit 2: PENDING porque trace_processor_shell no esta disponible.'
}

trace=''
metadata=''
trace_processor="${TRACE_PROCESSOR_SHELL:-}"
while (($# > 0)); do
  case "$1" in
    --trace)
      (($# >= 2)) || perfetto_die 'falta valor para --trace'
      trace="$2"
      shift 2
      ;;
    --metadata)
      (($# >= 2)) || perfetto_die 'falta valor para --metadata'
      metadata="$2"
      shift 2
      ;;
    --trace-processor)
      (($# >= 2)) || perfetto_die 'falta valor para --trace-processor'
      trace_processor="$2"
      shift 2
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

[[ -n "$trace" ]] || perfetto_die '--trace es obligatorio'
[[ -s "$trace" ]] || perfetto_die "la traza no existe o esta vacia: ${trace}"
[[ -n "$metadata" ]] || perfetto_die '--metadata es obligatorio'
[[ -r "$metadata" ]] || perfetto_die "no se puede leer metadata: ${metadata}"

metadata_package="$(perfetto_metadata_value "$metadata" package || true)"
target_uid="$(perfetto_metadata_value "$metadata" target_uid || true)"
target_app_id="$(perfetto_metadata_value "$metadata" target_app_id || true)"
target_pid="$(perfetto_metadata_value "$metadata" target_pid || true)"
expected_trace_sha256="$(
  perfetto_metadata_value "$metadata" trace_sha256 || true
)"
[[ "$metadata_package" == "$PERFETTO_PACKAGE" ]] ||
  perfetto_die "metadata pertenece a otro package: ${metadata_package:-ausente}"
perfetto_validate_uint target_uid "$target_uid"
perfetto_validate_uint target_app_id "$target_app_id"
perfetto_validate_uint target_pid "$target_pid"
[[ "$expected_trace_sha256" =~ ^[a-f0-9]{64}$ ]] ||
  perfetto_die 'trace_sha256 ausente o invalido en metadata'
actual_trace_sha256="$(sha256sum "$trace" | awk '{print $1}')"
[[ "$actual_trace_sha256" == "$expected_trace_sha256" ]] ||
  perfetto_die 'trace.pftrace no coincide con trace_sha256 de metadata'

using_default_trace_processor=0
if [[ -z "$trace_processor" ]]; then
  using_default_trace_processor=1
  trace_processor="$(perfetto_default_trace_processor)"
fi
if ((using_default_trace_processor == 1)) &&
  [[ ! -e "$trace_processor" && ! -L "$trace_processor" ]]; then
  printf '%s\n' \
    "PENDING: falta el trace_processor_shell fijado: ${trace_processor}" \
    'La captura no se considera PASS; ejecuta install_trace_processor.sh y repite.' >&2
  exit 2
fi
trace_processor="$(perfetto_validate_trace_processor "$trace_processor")"
trace_processor_release="$(perfetto_trace_processor_lock_value release)"
trace_processor_commit="$(perfetto_trace_processor_lock_value release_commit)"
trace_processor_sha256="$(
  perfetto_trace_processor_lock_value artifact_sha256
)"
trace_processor_version="$("$trace_processor" --version)"
trace_processor_version="${trace_processor_version%%$'\n'*}"

readonly sql_file="${SCRIPT_DIR}/verify_voice_trace.sql.in"
[[ -r "$sql_file" ]] || perfetto_die "falta la consulta: ${sql_file}"
rendered_sql="$(
  sed \
    -e "s/@PACKAGE@/${PERFETTO_PACKAGE}/g" \
    -e "s/@TARGET_UID@/${target_uid}/g" \
    -e "s/@TARGET_APP_ID@/${target_app_id}/g" \
    -e "s/@TARGET_PID@/${target_pid}/g" \
    "$sql_file"
)"
if grep -Eq '@[A-Z0-9_]+@' <<<"$rendered_sql"; then
  perfetto_die 'quedaron placeholders sin resolver en la consulta de verificacion'
fi

if ! query_output="$("$trace_processor" query "$trace" "$rendered_sql")"; then
  printf 'ERROR: trace_processor_shell no pudo analizar la traza:\n%s\n' "$query_output" >&2
  exit 1
fi

counts="$(printf '%s\n' "$query_output" | tail -n 1 | tr -d '"\r[:space:]')"
if [[ ! "$counts" =~ ^([0-9]+)\|([0-9]+)\|([0-9]+)\|([0-9]+)$ ]]; then
  printf 'ERROR: salida inesperada de trace_processor_shell: %s\n' "$query_output" >&2
  exit 1
fi

turns="${BASH_REMATCH[1]}"
points="${BASH_REMATCH[2]}"
starts="${BASH_REMATCH[3]}"
distinct_points="${BASH_REMATCH[4]}"
printf 'trace_sha256: %s\n' "$actual_trace_sha256"
printf 'trace_processor_release: %s\n' "$trace_processor_release"
printf 'trace_processor_commit: %s\n' "$trace_processor_commit"
printf 'trace_processor_sha256: %s\n' "$trace_processor_sha256"
printf 'trace_processor_version: %s\n' "$trace_processor_version"
printf 'hermes.voice.turn: %d\n' "$turns"
printf 'eventos de punto: %d\n' "$points"
printf 'turn_started: %d\n' "$starts"
printf 'puntos distintos: %d\n' "$distinct_points"

if ((turns < 1 || points < 2 || starts < 1 || distinct_points < 2)); then
  perfetto_die \
    'verificacion NO-GO: faltan hermes.voice.turn o al menos dos puntos de instrumentacion'
fi

printf 'Verificacion de instrumentacion Hermes: OK. Esto no valida latencia ni QA fisica.\n'
