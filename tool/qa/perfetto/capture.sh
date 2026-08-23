#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: capture.sh --output-dir DIR --apk APK --launch-receipt FILE' \
    '                  --route phone|server' \
    '                  --scenario normal|barge-in|stop|exit' \
    '                  [--serial SERIAL] [--duration-seconds N]' \
    '' \
    'DIR es obligatorio. N debe estar entre 10 y 300; por defecto 90.' \
    'No instala, no lanza, no detiene y no reinicia la app o el dispositivo.'
}

serial="${HERMES_QA_SERIAL:-$PERFETTO_DEFAULT_SERIAL}"
output_dir=''
apk=''
launch_receipt=''
route=''
scenario=''
duration_seconds=90
while (($# > 0)); do
  case "$1" in
    --output-dir)
      (($# >= 2)) || perfetto_die 'falta valor para --output-dir'
      output_dir="$2"
      shift 2
      ;;
    --apk)
      (($# >= 2)) || perfetto_die 'falta valor para --apk'
      apk="$2"
      shift 2
      ;;
    --launch-receipt)
      (($# >= 2)) || perfetto_die 'falta valor para --launch-receipt'
      launch_receipt="$2"
      shift 2
      ;;
    --route)
      (($# >= 2)) || perfetto_die 'falta valor para --route'
      route="$2"
      shift 2
      ;;
    --scenario)
      (($# >= 2)) || perfetto_die 'falta valor para --scenario'
      scenario="$2"
      shift 2
      ;;
    --serial)
      (($# >= 2)) || perfetto_die 'falta valor para --serial'
      serial="$2"
      shift 2
      ;;
    --duration-seconds)
      (($# >= 2)) || perfetto_die 'falta valor para --duration-seconds'
      duration_seconds="$2"
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

[[ -n "$output_dir" ]] || perfetto_die '--output-dir es obligatorio'
[[ -n "$apk" ]] || perfetto_die '--apk es obligatorio'
[[ -f "$apk" ]] || perfetto_die "el APK local no existe: ${apk}"
[[ "$apk" != *$'\n'* ]] || perfetto_die 'la ruta del APK contiene un salto de linea'
[[ -n "$launch_receipt" ]] || perfetto_die '--launch-receipt es obligatorio'
[[ -r "$launch_receipt" ]] ||
  perfetto_die "no se puede leer launch receipt: ${launch_receipt}"
case "$route" in
  phone | server) ;;
  *) perfetto_die '--route debe ser phone o server' ;;
esac
case "$scenario" in
  normal | barge-in | stop | exit) ;;
  *) perfetto_die '--scenario debe ser normal, barge-in, stop o exit' ;;
esac
[[ "$duration_seconds" =~ ^[0-9]+$ ]] ||
  perfetto_die '--duration-seconds debe ser un entero'
((duration_seconds >= 10 && duration_seconds <= 300)) ||
  perfetto_die '--duration-seconds debe estar entre 10 y 300'
perfetto_validate_serial "$serial"
adb_bin="$(perfetto_resolve_adb)"
readonly adb_bin
timeout_bin="$(command -v timeout || true)"
[[ -n "$timeout_bin" && -x "$timeout_bin" ]] ||
  perfetto_die 'no se encontro timeout(1) para acotar la captura host'
readonly timeout_bin

mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"
[[ "$output_dir" != '/' ]] || perfetto_die 'el directorio de salida no puede ser /'

readonly rendered_config="${output_dir}/config.textproto"
readonly trace_file="${output_dir}/trace.pftrace"
readonly capture_stderr="${output_dir}/capture.stderr"
readonly doctor_report="${output_dir}/doctor.txt"
readonly verification_report="${output_dir}/verification.txt"
readonly metadata_file="${output_dir}/metadata.txt"

for reserved in \
  "$rendered_config" \
  "$trace_file" \
  "$capture_stderr" \
  "$doctor_report" \
  "$verification_report" \
  "$metadata_file"; do
  [[ ! -e "$reserved" ]] ||
    perfetto_die "se rehusa sobrescribir salida existente: ${reserved}"
done

"${SCRIPT_DIR}/doctor.sh" --serial "$serial" | tee "$doctor_report"

apk_dir="$(cd -- "$(dirname -- "$apk")" && pwd -P)"
apk_path="${apk_dir}/$(basename -- "$apk")"
apk_sha256="$(sha256sum "$apk_path" | awk '{print $1}')"
apk_size_bytes="$(stat -c '%s' -- "$apk_path")"

device_fingerprint="$($adb_bin -s "$serial" shell getprop ro.build.fingerprint 2>/dev/null | tr -d '\r\n')"
[[ -n "$device_fingerprint" ]] || perfetto_die 'no se pudo leer ro.build.fingerprint'

package_uid_output="$($adb_bin -s "$serial" shell cmd package list packages -U "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r')"
if [[ "$package_uid_output" =~ uid:([0-9]+) ]]; then
  target_uid="${BASH_REMATCH[1]}"
else
  perfetto_die "no se pudo resolver UID para ${PERFETTO_PACKAGE}"
fi
target_app_id=$((target_uid % 100000))

pid_output="$($adb_bin -s "$serial" shell pidof "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
read -r -a target_pids <<<"$pid_output"
if ((${#target_pids[@]} != 1)) || [[ ! "${target_pids[0]:-}" =~ ^[0-9]+$ ]]; then
  perfetto_die \
    "se requiere un unico PID activo para ${PERFETTO_PACKAGE}; recibido: ${pid_output:-ninguno}"
fi
target_pid="${target_pids[0]}"

receipt_package="$(perfetto_metadata_value "$launch_receipt" package || true)"
receipt_serial="$(perfetto_metadata_value "$launch_receipt" serial || true)"
receipt_fingerprint="$(perfetto_metadata_value "$launch_receipt" device_fingerprint || true)"
receipt_uid="$(perfetto_metadata_value "$launch_receipt" uid || true)"
receipt_pid="$(perfetto_metadata_value "$launch_receipt" pid || true)"
receipt_proc_start_ticks="$(perfetto_metadata_value "$launch_receipt" proc_start_ticks || true)"
receipt_opt_in="$(perfetto_metadata_value "$launch_receipt" trace_systrace || true)"
[[ "$receipt_package" == "$PERFETTO_PACKAGE" ]] || perfetto_die 'launch receipt: package no coincide'
[[ "$receipt_serial" == "$serial" ]] || perfetto_die 'launch receipt: serial no coincide'
[[ "$receipt_fingerprint" == "$device_fingerprint" ]] ||
  perfetto_die 'launch receipt: fingerprint no coincide'
[[ "$receipt_uid" == "$target_uid" ]] || perfetto_die 'launch receipt: UID no coincide'
[[ "$receipt_pid" == "$target_pid" ]] || perfetto_die 'launch receipt: PID no coincide'
current_proc_stat="$($adb_bin -s "$serial" shell cat "/proc/${target_pid}/stat" 2>/dev/null || true)"
current_proc_fields="${current_proc_stat##*) }"
read -r -a current_fields <<<"$current_proc_fields"
current_proc_start_ticks="${current_fields[19]:-}"
[[ "$receipt_proc_start_ticks" =~ ^[0-9]+$ ]] ||
  perfetto_die 'launch receipt: proc_start_ticks invalido'
[[ "$receipt_proc_start_ticks" == "$current_proc_start_ticks" ]] ||
  perfetto_die 'launch receipt: el PID fue reciclado o reiniciado'
[[ "$receipt_opt_in" == 'true' ]] || perfetto_die 'launch receipt: falta trace_systrace=true'
launch_receipt_sha256="$(sha256sum "$launch_receipt" | awk '{print $1}')"

process_status="$($adb_bin -s "$serial" shell cat "/proc/${target_pid}/status" 2>/dev/null || true)"
process_uid="$(awk '$1 == "Uid:" { print $2; exit }' <<<"$process_status")"
[[ "$process_uid" == "$target_uid" ]] ||
  perfetto_die "UID de package (${target_uid}) y proceso (${process_uid:-ausente}) no coinciden"

installed_apk_output="$($adb_bin -s "$serial" shell pm path "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r')"
installed_apk_path="${installed_apk_output#package:}"
[[ -n "$installed_apk_path" && "$installed_apk_path" != "$installed_apk_output" ]] ||
  perfetto_die 'no se pudo resolver el APK instalado'

package_dump="$($adb_bin -s "$serial" shell dumpsys package "$PERFETTO_PACKAGE" 2>/dev/null)"
installed_version_name="$(awk -F= '/versionName=/ { print $2; exit }' <<<"$package_dump")"
version_code_line="$(awk '/versionCode=/ { print; exit }' <<<"$package_dump")"
if [[ "$version_code_line" =~ versionCode=([0-9]+) ]]; then
  installed_version_code="${BASH_REMATCH[1]}"
else
  perfetto_die 'no se pudo resolver versionCode del package instalado'
fi

duration_ms=$((duration_seconds * 1000))
capture_watchdog_seconds=$((duration_seconds + 30))
sed \
  -e "s/@DURATION_MS@/${duration_ms}/g" \
  -e "s/@PACKAGE@/${PERFETTO_PACKAGE}/g" \
  "${SCRIPT_DIR}/qa_profile.textproto.in" >"$rendered_config"
if grep -Eq '@[A-Z0-9_]+@' "$rendered_config"; then
  perfetto_die 'quedaron placeholders sin resolver en config.textproto'
fi

started_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
config_sha256="$(sha256sum "$rendered_config" | awk '{print $1}')"
capture_id="$(
  printf '%s\0' \
    "$PERFETTO_PACKAGE" "$serial" "$started_utc" "$config_sha256" \
    "$apk_sha256" "$target_uid" "$target_pid" "$route" "$scenario" |
    sha256sum | awk '{print substr($1, 1, 16)}'
)"
printf '%s\n' \
  "capture_id=${capture_id}" \
  "package=${PERFETTO_PACKAGE}" \
  "serial=${serial}" \
  "device_fingerprint=${device_fingerprint}" \
  "route=${route}" \
  "scenario=${scenario}" \
  "target_uid=${target_uid}" \
  "target_app_id=${target_app_id}" \
  "target_pid=${target_pid}" \
  "proc_start_ticks=${current_proc_start_ticks}" \
  "launch_receipt_sha256=${launch_receipt_sha256}" \
  "apk_file=$(basename -- "$apk_path")" \
  "apk_size_bytes=${apk_size_bytes}" \
  "apk_sha256=${apk_sha256}" \
  "installed_apk_path=${installed_apk_path}" \
  "installed_version_name=${installed_version_name}" \
  "installed_version_code=${installed_version_code}" \
  "duration_seconds=${duration_seconds}" \
  "host_watchdog_seconds=${capture_watchdog_seconds}" \
  "started_utc=${started_utc}" \
  "config_sha256=${config_sha256}" >"$metadata_file"

printf 'Capturando %d segundos en %s...\n' "$duration_seconds" "$trace_file"
# `adb exec-out` no transporta stdin de forma fiable en adb 37/Android 17 y
# puede dejar Perfetto bloqueado en n_tty_read antes de leer el config. El shell
# sin PTY conserva stdin, stdout binario y el exit remoto. `exec` liga la vida
# de Perfetto a esa conexion para que cerrar/matar adb no deje un shell padre.
set +e
"$timeout_bin" --verbose --signal=TERM --kill-after=10s \
  "${capture_watchdog_seconds}s" \
  "$adb_bin" -s "$serial" shell -T \
  exec perfetto --txt -c - -o - \
  <"$rendered_config" >"$trace_file" 2>"$capture_stderr"
capture_status=$?
set -e
case "$capture_status" in
  0) ;;
  124 | 137)
    perfetto_die \
      "la captura excedio el watchdog host de ${capture_watchdog_seconds}s; revisa ${capture_stderr}"
    ;;
  *)
    perfetto_die \
      "la captura Perfetto fallo (exit ${capture_status}); revisa ${capture_stderr}"
    ;;
esac
[[ -s "$trace_file" ]] || perfetto_die 'Perfetto produjo una traza vacia'

trace_sha256="$(sha256sum "$trace_file" | awk '{print $1}')"
ended_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
pid_at_end="$($adb_bin -s "$serial" shell pidof "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true)"
printf '%s\n' \
  "ended_utc=${ended_utc}" \
  "pid_at_end=${pid_at_end:-none}" \
  "trace_sha256=${trace_sha256}" >>"$metadata_file"
printf 'Traza capturada: %s\n' "$trace_file"

set +e
"${SCRIPT_DIR}/verify_trace.sh" \
  --trace "$trace_file" \
  --metadata "$metadata_file" 2>&1 |
  tee "$verification_report"
verify_status=${PIPESTATUS[0]}
set -e

case "$verify_status" in
  0)
    printf 'Captura y presencia de instrumentacion verificadas. QA de rendimiento sigue separada.\n'
    ;;
  2)
    printf 'Captura completa; verificacion PENDING por falta de trace_processor_shell.\n' >&2
    exit 2
    ;;
  *)
    perfetto_die "la traza no supera el gate Hermes; revisa ${verification_report}"
    ;;
esac
