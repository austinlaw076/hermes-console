#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: launch_trace_opt_in.sh --receipt FILE [--serial SERIAL]' \
    '' \
    'Inicia el paquete QA detenido con --ez trace-systrace true.' \
    'Escribe un recibo package/UID/PID que capture.sh exige despues.' \
    'Nunca fuerza la parada ni reinicia el proceso o el dispositivo.'
}

serial="${HERMES_QA_SERIAL:-$PERFETTO_DEFAULT_SERIAL}"
receipt=''
while (($# > 0)); do
  case "$1" in
    --receipt)
      (($# >= 2)) || perfetto_die 'falta valor para --receipt'
      receipt="$2"
      shift 2
      ;;
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
[[ -n "$receipt" ]] || perfetto_die '--receipt es obligatorio'
[[ "$receipt" != *$'\n'* ]] || perfetto_die 'receipt contiene un salto de linea'
receipt_parent="$(dirname -- "$receipt")"
mkdir -p -- "$receipt_parent"
receipt_parent="$(cd -- "$receipt_parent" && pwd -P)"
receipt="${receipt_parent}/$(basename -- "$receipt")"
[[ ! -e "$receipt" ]] || perfetto_die "se rehusa sobrescribir receipt: ${receipt}"
adb_bin="$(perfetto_resolve_adb)"
readonly adb_bin

state="$($adb_bin -s "$serial" get-state 2>/dev/null || true)"
[[ "$state" == 'device' ]] ||
  perfetto_die "el dispositivo ${serial} no esta disponible"

package_path="$($adb_bin -s "$serial" shell pm path "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
[[ "$package_path" == package:* ]] ||
  perfetto_die "el paquete fijo ${PERFETTO_PACKAGE} no esta instalado"

launcher_component="$($adb_bin -s "$serial" shell cmd package \
  resolve-activity --brief --components \
  -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER \
  "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
[[ -n "$launcher_component" && "$launcher_component" != *$'\n'* ]] ||
  perfetto_die 'no se resolvio una unica Activity launcher'
launcher_package="${launcher_component%%/*}"
launcher_activity="${launcher_component#*/}"
[[ "$launcher_component" == */* &&
  "$launcher_package" == "$PERFETTO_PACKAGE" ]] ||
  perfetto_die \
    "la Activity resuelta no pertenece a ${PERFETTO_PACKAGE}: ${launcher_component}"
[[ -n "$launcher_activity" && "$launcher_activity" != */* &&
  "$launcher_activity" =~ ^[A-Za-z0-9_.\$]+$ ]] ||
  perfetto_die "nombre de Activity launcher no valido: ${launcher_activity}"

process_ids="$($adb_bin -s "$serial" shell pidof "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
if [[ -n "$process_ids" ]]; then
  perfetto_die \
    "${PERFETTO_PACKAGE} ya tiene proceso (${process_ids}); no se reinicia automaticamente. Detenlo de forma explicita y vuelve a ejecutar."
fi

$adb_bin -s "$serial" shell am start -W \
  -n "$launcher_component" \
  -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER \
  --ez trace-systrace true

launched_pid="$($adb_bin -s "$serial" shell pidof "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
[[ "$launched_pid" =~ ^[0-9]+$ ]] ||
  perfetto_die "no se resolvio un PID unico tras el arranque: ${launched_pid:-ninguno}"
proc_stat="$($adb_bin -s "$serial" shell cat "/proc/${launched_pid}/stat" 2>/dev/null || true)"
proc_stat_fields="${proc_stat##*) }"
read -r -a proc_fields <<<"$proc_stat_fields"
proc_start_ticks="${proc_fields[19]:-}"
[[ "$proc_start_ticks" =~ ^[0-9]+$ ]] ||
  perfetto_die 'no se pudo fijar starttime del proceso lanzado'
uid_output="$($adb_bin -s "$serial" shell cmd package list packages -U "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r')"
[[ "$uid_output" =~ uid:([0-9]+) ]] || perfetto_die 'no se pudo resolver UID tras el arranque'
launched_uid="${BASH_REMATCH[1]}"
fingerprint="$($adb_bin -s "$serial" shell getprop ro.build.fingerprint 2>/dev/null | tr -d '\r\n')"
[[ -n "$fingerprint" ]] || perfetto_die 'no se pudo resolver fingerprint'
printf '%s\n' \
  "package=${PERFETTO_PACKAGE}" \
  "launcher_component=${launcher_component}" \
  "serial=${serial}" \
  "device_fingerprint=${fingerprint}" \
  "uid=${launched_uid}" \
  "pid=${launched_pid}" \
  "proc_start_ticks=${proc_start_ticks}" \
  'trace_systrace=true' \
  "launched_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >"$receipt"

printf '%s\n' \
  "Arranque opt-in solicitado para ${PERFETTO_PACKAGE}." \
  "Recibo obligatorio creado: ${receipt}" \
  'Esto no demuestra que haya puntos Hermes: verify_trace.sh es el gate posterior.'
