#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: doctor.sh [--serial SERIAL]' \
    '' \
    'Requiere --serial o HERMES_QA_SERIAL; no hay serial físico versionado.' \
    'Solo ejecuta comprobaciones read-only y perfetto --query --long.'
}

serial="${HERMES_QA_SERIAL:-$PERFETTO_DEFAULT_SERIAL}"
while (($# > 0)); do
  case "$1" in
    --serial)
      (($# >= 2)) || perfetto_die 'falta valor para --serial'
      serial="$2"
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

perfetto_validate_serial "$serial"
adb_bin="$(perfetto_resolve_adb)"
readonly adb_bin
readonly template="${SCRIPT_DIR}/qa_profile.textproto.in"
[[ -r "$template" ]] || perfetto_die "no se puede leer el template: ${template}"
perfetto_validate_trace_processor_lock

readonly -a analysis_files=(
  "${SCRIPT_DIR}/analyze_trace.sh"
  "${SCRIPT_DIR}/install_trace_processor.sh"
  "${SCRIPT_DIR}/trace_processor.lock"
  "${SCRIPT_DIR}/verify_trace.sh"
  "${SCRIPT_DIR}/voice_latency_metrics.sql"
  "${SCRIPT_DIR}/frame_process_metrics.sql"
)
for analysis_file in "${analysis_files[@]}"; do
  [[ -r "$analysis_file" ]] || perfetto_die "falta archivo T042C: ${analysis_file}"
done
if grep -Eq '\$adb_bin|(^|[[:space:]])adb[[:space:]]+-' \
  "${SCRIPT_DIR}/analyze_trace.sh"; then
  perfetto_die 'analyze_trace.sh no puede ejecutar adb'
fi
for sql_file in \
  "${SCRIPT_DIR}/voice_latency_metrics.sql" \
  "${SCRIPT_DIR}/frame_process_metrics.sql"; do
  for placeholder in PACKAGE TARGET_UID TARGET_APP_ID TARGET_PID ROUTE SCENARIO; do
    grep -Fq "@${placeholder}@" "$sql_file" ||
      perfetto_die "falta @${placeholder}@ en ${sql_file}"
  done
  if grep -Eqi 'transcript|cookie|token|audio_pcm|session_text|model_url' "$sql_file"; then
    perfetto_die "consulta contiene un campo de contenido prohibido: ${sql_file}"
  fi
  grep -Fq 'sample_count' "$sql_file" ||
    perfetto_die "consulta sin sample_count: ${sql_file}"
  grep -Fq 'available' "$sql_file" ||
    perfetto_die "consulta sin available: ${sql_file}"
done
for voice_contract_field in \
  stt_topology \
  last_above \
  suffix_append_latency \
  pcm_accept_latency; do
  grep -Fq "$voice_contract_field" \
    "${SCRIPT_DIR}/voice_latency_metrics.sql" ||
    perfetto_die \
      "consulta de voz no reconoce contrato: ${voice_contract_field}"
done

if grep -Fq 'android.ui.jank' "$template"; then
  perfetto_die 'el template solicita android.ui.jank standalone'
fi
if grep -Eq 'android\.log|logcat' "$template"; then
  perfetto_die 'el template contiene una fuente de log no permitida'
fi

mapfile -t configured_sources < <(
  sed -nE 's/^[[:space:]]*name:[[:space:]]*"([^"]+)".*/\1/p' "$template"
)

if ((${#configured_sources[@]} != ${#PERFETTO_ALLOWED_SOURCES[@]})); then
  perfetto_die \
    "el template debe declarar exactamente ${#PERFETTO_ALLOWED_SOURCES[@]} fuentes; declara ${#configured_sources[@]}"
fi

for source in "${configured_sources[@]}"; do
  perfetto_source_is_allowed "$source" ||
    perfetto_die "fuente fuera de la allowlist: ${source}"
done
for source in "${PERFETTO_ALLOWED_SOURCES[@]}"; do
  count="$(printf '%s\n' "${configured_sources[@]}" | grep -Fxc -- "$source" || true)"
  [[ "$count" == '1' ]] ||
    perfetto_die "la fuente ${source} debe aparecer exactamente una vez; aparece ${count}"
done

state="$($adb_bin -s "$serial" get-state 2>/dev/null || true)"
[[ "$state" == 'device' ]] ||
  perfetto_die "el dispositivo ${serial} no esta disponible (estado: ${state:-desconocido})"

package_path="$($adb_bin -s "$serial" shell pm path "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
[[ "$package_path" == package:* ]] ||
  perfetto_die "el paquete fijo ${PERFETTO_PACKAGE} no esta instalado en ${serial}"

# Intencionadamente no se usa --query-raw: su salida es protobuf binario y
# requeriria decodificacion explicita.
if ! query_output="$($adb_bin -s "$serial" shell perfetto --query --long 2>&1)"; then
  perfetto_die "perfetto --query --long fallo en ${serial}"
fi
query_output="${query_output//$'\r'/}"

missing_required=0
missing_supplemental=0
printf 'Package fijo: %s\n' "$PERFETTO_PACKAGE"
printf 'Pixel/serial:  %s\n' "$serial"
printf 'Consulta:      adb shell perfetto --query --long\n\n'
printf '%-14s %-45s %s\n' 'CLASE' 'FUENTE' 'DISPONIBLE'
printf '%-14s %-45s %s\n' '--------------' '---------------------------------------------' '----------'

for source in "${PERFETTO_REQUIRED_SOURCES[@]}"; do
  if perfetto_query_has_source "$query_output" "$source"; then
    available='si'
  else
    available='NO'
    missing_required=$((missing_required + 1))
  fi
  printf '%-14s %-45s %s\n' 'requerida' "$source" "$available"
done

for source in "${PERFETTO_SUPPLEMENTAL_SOURCES[@]}"; do
  if perfetto_query_has_source "$query_output" "$source"; then
    available='si'
  else
    available='NO'
    missing_supplemental=$((missing_supplemental + 1))
  fi
  printf '%-14s %-45s %s\n' 'suplementaria' "$source" "$available"
done

printf '\nandroid.ui.jank standalone: no solicitado (FrameTimeline es la fuente canonica).\n'
printf 'Fuentes requeridas ausentes: %d\n' "$missing_required"
printf 'Fuentes suplementarias ausentes: %d\n' "$missing_supplemental"

if ((missing_required > 0)); then
  perfetto_die 'doctor NO-GO: faltan fuentes requeridas; no ejecutar captura'
fi

if ((missing_supplemental > 0)); then
  printf 'Doctor OK con evidencia suplementaria PENDING por soporte del dispositivo.\n'
else
  printf 'Doctor OK: las diez fuentes de la allowlist estan disponibles.\n'
fi
