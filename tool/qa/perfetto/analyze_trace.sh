#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: analyze_trace.sh --capture-dir DIR --output-dir DIR' \
    '                         [--trace-processor RUTA]' \
    '' \
    'Analiza una captura existente; no usa adb, no lanza ni captura la app.' \
    'Exit 2: PENDING si trace_processor_shell no esta disponible.'
}

capture_dir=''
output_dir=''
trace_processor="${TRACE_PROCESSOR_SHELL:-}"
while (($# > 0)); do
  case "$1" in
    --capture-dir)
      (($# >= 2)) || perfetto_die 'falta valor para --capture-dir'
      capture_dir="$2"
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || perfetto_die 'falta valor para --output-dir'
      output_dir="$2"
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

[[ -n "$capture_dir" ]] || perfetto_die '--capture-dir es obligatorio'
[[ -d "$capture_dir" ]] || perfetto_die "capture-dir no existe: ${capture_dir}"
capture_dir="$(cd -- "$capture_dir" && pwd -P)"
[[ -n "$output_dir" ]] || perfetto_die '--output-dir es obligatorio'

readonly trace_file="${capture_dir}/trace.pftrace"
readonly metadata_file="${capture_dir}/metadata.txt"
[[ -s "$trace_file" ]] || perfetto_die "falta trace.pftrace: ${trace_file}"
[[ -r "$metadata_file" ]] || perfetto_die "falta metadata.txt: ${metadata_file}"

metadata_package="$(perfetto_metadata_value "$metadata_file" package || true)"
target_uid="$(perfetto_metadata_value "$metadata_file" target_uid || true)"
target_app_id="$(perfetto_metadata_value "$metadata_file" target_app_id || true)"
target_pid="$(perfetto_metadata_value "$metadata_file" target_pid || true)"
route="$(perfetto_metadata_value "$metadata_file" route || true)"
scenario="$(perfetto_metadata_value "$metadata_file" scenario || true)"
expected_trace_sha256="$(perfetto_metadata_value "$metadata_file" trace_sha256 || true)"
capture_id="$(perfetto_metadata_value "$metadata_file" capture_id || true)"

[[ "$metadata_package" == "$PERFETTO_PACKAGE" ]] ||
  perfetto_die "metadata pertenece a otro package: ${metadata_package:-ausente}"
perfetto_validate_uint target_uid "$target_uid"
perfetto_validate_uint target_app_id "$target_app_id"
perfetto_validate_uint target_pid "$target_pid"
case "$route" in phone | server) ;; *) perfetto_die 'route invalida en metadata' ;; esac
case "$scenario" in
  normal | barge-in | stop | exit) ;;
  *) perfetto_die 'scenario invalido en metadata' ;;
esac
[[ "$capture_id" =~ ^[a-f0-9]{16}$ ]] || perfetto_die 'capture_id invalido en metadata'
[[ "$expected_trace_sha256" =~ ^[a-f0-9]{64}$ ]] ||
  perfetto_die 'trace_sha256 ausente o invalido en metadata'
actual_trace_sha256="$(sha256sum "$trace_file" | awk '{print $1}')"
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
    'Ejecuta install_trace_processor.sh y repite el analisis.' \
    'No se generan metricas ni se considera PASS.' >&2
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

mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"
[[ "$output_dir" != '/' ]] || perfetto_die 'output-dir no puede ser /'
readonly voice_csv="${output_dir}/voice_latency_metrics.csv"
readonly process_csv="${output_dir}/frame_process_metrics.csv"
readonly voice_stderr="${output_dir}/voice_latency_metrics.stderr"
readonly process_stderr="${output_dir}/frame_process_metrics.stderr"
readonly analysis_metadata="${output_dir}/analysis_metadata.txt"
for reserved in "$voice_csv" "$process_csv" "$voice_stderr" \
  "$process_stderr" "$analysis_metadata"; do
  [[ ! -e "$reserved" ]] || perfetto_die "se rehusa sobrescribir: ${reserved}"
done

scenario_trace="${scenario//-/_}"
render_sql() {
  local sql_file="$1"
  sed \
    -e "s/@PACKAGE@/${PERFETTO_PACKAGE}/g" \
    -e "s/@TARGET_UID@/${target_uid}/g" \
    -e "s/@TARGET_APP_ID@/${target_app_id}/g" \
    -e "s/@TARGET_PID@/${target_pid}/g" \
    -e "s/@ROUTE@/${route}/g" \
    -e "s/@SCENARIO@/${scenario_trace}/g" \
    "$sql_file"
}

run_query() {
  local sql_file="$1"
  local csv_file="$2"
  local stderr_file="$3"
  local rendered_sql
  rendered_sql="$(render_sql "$sql_file")"
  if grep -Eq '@[A-Z0-9_]+@' <<<"$rendered_sql"; then
    perfetto_die "placeholders sin resolver en ${sql_file}"
  fi
  if ! "$trace_processor" query "$trace_file" "$rendered_sql" \
    >"$csv_file" 2>"$stderr_file"; then
    perfetto_die "consulta fallida: ${sql_file}; revisa ${stderr_file}"
  fi
  [[ -s "$csv_file" ]] || perfetto_die "consulta sin salida CSV: ${sql_file}"
  local csv_header
  csv_header="$(awk 'NF { print; exit }' "$csv_file")"
  [[ "$csv_header" == *'"sample_count"'* &&
     "$csv_header" == *'"available"'* ]] ||
    perfetto_die "consulta sin cabecera contractual CSV: ${sql_file}"
}

readonly voice_sql="${SCRIPT_DIR}/voice_latency_metrics.sql"
readonly process_sql="${SCRIPT_DIR}/frame_process_metrics.sql"
run_query "$voice_sql" "$voice_csv" "$voice_stderr"
run_query "$process_sql" "$process_csv" "$process_stderr"

printf '%s\n' \
  "capture_id=${capture_id}" \
  "package=${PERFETTO_PACKAGE}" \
  "target_uid=${target_uid}" \
  "target_app_id=${target_app_id}" \
  "target_pid=${target_pid}" \
  "route=${route}" \
  "scenario=${scenario}" \
  "trace_sha256=${actual_trace_sha256}" \
  "trace_processor_release=${trace_processor_release}" \
  "trace_processor_commit=${trace_processor_commit}" \
  "trace_processor_sha256=${trace_processor_sha256}" \
  "trace_processor_version=${trace_processor_version}" \
  "voice_sql_sha256=$(sha256sum "$voice_sql" | awk '{print $1}')" \
  "frame_process_sql_sha256=$(sha256sum "$process_sql" | awk '{print $1}')" \
  "analyzed_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$analysis_metadata"

printf '%s\n' \
  "Metricas de voz: ${voice_csv}" \
  "Metricas de frames/proceso: ${process_csv}" \
  'Cada fila incluye sample_count y available; NULL significa sin evidencia, no cero.'
