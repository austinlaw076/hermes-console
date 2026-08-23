#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf '%s\n' \
    'Uso: post_exit_observe.sh --capture-metadata metadata.txt --output-dir DIR' \
    '                            [--serial SERIAL]' \
    '' \
    'Muestrea 11 veces durante 600 s en un proceso separado de la captura.' \
    'No lanza/detiene la app, no captura Perfetto y no resetea contadores.' \
    'CPU/PSS/bateria quedan PENDING sin baseline idle comparable.'
}

parse_total_pss_kb() {
  awk '
    /TOTAL PSS:/ {
      value = $0
      sub(/^.*TOTAL PSS:[[:space:]]*/, "", value)
      sub(/[[:space:]].*$/, "", value)
      if (value ~ /^[0-9]+$/) {
        print value
        found = 1
        exit
      }
    }
    /^[[:space:]]*TOTAL[[:space:]]+[0-9]+/ && fallback == "" {
      fallback = $2
    }
    END {
      if (!found && fallback ~ /^[0-9]+$/) print fallback
    }
  '
}

thermal_max_c() {
  local category="$1"
  awk -v category="$category" '
    /Temperature\{/ {
      value = $0
      sub(/^.*mValue=/, "", value)
      sub(/[,}].*$/, "", value)

      type = $0
      sub(/^.*mType=/, "", type)
      sub(/[,}].*$/, "", type)

      name = $0
      sub(/^.*mName=/, "", name)
      sub(/[,}].*$/, "", name)
      lower_name = tolower(name)

      wanted = 0
      if (category == "skin") {
        wanted = type == "3" || lower_name ~ /skin/
      } else if (category == "cpu_soc") {
        wanted = type == "0" ||
          lower_name ~ /(^|[-_[:space:]])(cpu|soc|ap)([-_[:space:]]|$)/
      }

      if (wanted && value ~ /^-?[0-9]+([.][0-9]+)?$/) {
        numeric = value + 0
        if (!found || numeric > maximum) maximum = numeric
        found = 1
      }
    }
    END {
      if (found) printf "%.3f", maximum
    }
  '
}

serial="${HERMES_QA_SERIAL:-$PERFETTO_DEFAULT_SERIAL}"
capture_metadata=''
output_dir=''
while (($# > 0)); do
  case "$1" in
    --capture-metadata)
      (($# >= 2)) || perfetto_die 'falta valor para --capture-metadata'
      capture_metadata="$2"
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || perfetto_die 'falta valor para --output-dir'
      output_dir="$2"
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
[[ -n "$capture_metadata" ]] || perfetto_die '--capture-metadata es obligatorio'
[[ -r "$capture_metadata" ]] ||
  perfetto_die "no se puede leer capture metadata: ${capture_metadata}"
[[ -n "$output_dir" ]] || perfetto_die '--output-dir es obligatorio'

metadata_package="$(perfetto_metadata_value "$capture_metadata" package || true)"
metadata_serial="$(perfetto_metadata_value "$capture_metadata" serial || true)"
metadata_scenario="$(perfetto_metadata_value "$capture_metadata" scenario || true)"
capture_id="$(perfetto_metadata_value "$capture_metadata" capture_id || true)"
target_uid="$(perfetto_metadata_value "$capture_metadata" target_uid || true)"
target_pid="$(perfetto_metadata_value "$capture_metadata" target_pid || true)"
target_proc_start_ticks="$(
  perfetto_metadata_value "$capture_metadata" proc_start_ticks || true
)"
expected_fingerprint="$(
  perfetto_metadata_value "$capture_metadata" device_fingerprint || true
)"
[[ "$metadata_package" == "$PERFETTO_PACKAGE" ]] ||
  perfetto_die 'capture metadata pertenece a otro package'
[[ "$metadata_serial" == "$serial" ]] ||
  perfetto_die "serial no coincide con capture metadata: ${metadata_serial}"
[[ "$metadata_scenario" == 'exit' ]] ||
  perfetto_die 'la observacion de 10 min exige una captura --scenario exit'
[[ "$capture_id" =~ ^[a-f0-9]{16}$ ]] || perfetto_die 'capture_id invalido'
perfetto_validate_uint target_uid "$target_uid"
perfetto_validate_uint target_pid "$target_pid"
perfetto_validate_uint target_proc_start_ticks "$target_proc_start_ticks"

adb_bin="$(perfetto_resolve_adb)"
readonly adb_bin
state="$($adb_bin -s "$serial" get-state 2>/dev/null || true)"
[[ "$state" == 'device' ]] || perfetto_die "Pixel no disponible: ${serial}"
current_fingerprint="$(
  $adb_bin -s "$serial" shell getprop ro.build.fingerprint 2>/dev/null |
    tr -d '\r\n'
)"
[[ "$current_fingerprint" == "$expected_fingerprint" ]] ||
  perfetto_die 'fingerprint actual no coincide con la captura'
uid_output="$(
  $adb_bin -s "$serial" shell cmd package list packages -U \
    "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r'
)"
[[ "$uid_output" =~ uid:([0-9]+) ]] ||
  perfetto_die 'no se pudo resolver UID actual'
[[ "${BASH_REMATCH[1]}" == "$target_uid" ]] ||
  perfetto_die 'UID actual no coincide con la captura'

device_clk_tck="$(
  $adb_bin -s "$serial" shell getconf CLK_TCK 2>/dev/null | tr -d '\r[:space:]' || true
)"
if [[ ! "$device_clk_tck" =~ ^[1-9][0-9]*$ ]]; then
  device_clk_tck='NA'
fi

mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"
[[ "$output_dir" != '/' ]] || perfetto_die 'output-dir no puede ser /'
readonly samples_file="${output_dir}/post_exit_samples.csv"
readonly summary_file="${output_dir}/post_exit_summary.txt"
readonly observation_metadata="${output_dir}/post_exit_metadata.txt"
for reserved in "$samples_file" "$summary_file" "$observation_metadata"; do
  [[ ! -e "$reserved" ]] || perfetto_die "se rehusa sobrescribir: ${reserved}"
done

readonly interval_seconds=60
readonly final_sample=10
started_epoch="$(date -u +'%s')"
started_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf '%s\n' \
  'timestamp_utc,elapsed_s,current_pids,target_pid_alive,target_pid_identity_match,vmrss_kb,vmrss_available,vmswap_kb,vmswap_available,pss_kb,pss_available,threads,threads_available,cpu_total_ticks,cpu_delta_ticks,cpu_delta_elapsed_s,cpu_percent_one_core,cpu_available,record_audio_running,foreground_service,battery_level,battery_level_available,battery_temp_decic,battery_temp_available,charge_counter_uah,charge_counter_available,usb_powered,usb_powered_available,thermal_status,thermal_status_available,skin_temp_c,skin_temp_available,cpu_soc_temp_c,cpu_soc_temp_available' \
  >"$samples_file"

previous_cpu_ticks=''
previous_cpu_epoch=''
for ((sample = 0; sample <= final_sample; sample++)); do
  now_epoch="$(date -u +'%s')"
  now_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  elapsed_seconds=$((now_epoch - started_epoch))

  current_pids="$(
    $adb_bin -s "$serial" shell pidof "$PERFETTO_PACKAGE" 2>/dev/null |
      tr -d '\r' | tr '\n' ' ' || true
  )"
  current_pids="${current_pids% }"
  current_pids_csv="${current_pids// /+}"
  target_pid_alive=0
  target_pid_identity_match=0
  for current_pid in $current_pids; do
    if [[ "$current_pid" == "$target_pid" ]]; then
      target_pid_alive=1
      break
    fi
  done

  vmrss_kb='NA'
  vmrss_available=0
  vmswap_kb='NA'
  vmswap_available=0
  pss_kb='NA'
  pss_available=0
  threads='NA'
  threads_available=0
  cpu_total_ticks='NA'
  cpu_delta_ticks='NA'
  cpu_delta_elapsed_s='NA'
  cpu_percent_one_core='NA'
  cpu_available=0

  if ((target_pid_alive == 1)); then
    target_proc_stat="$(
      $adb_bin -s "$serial" shell cat "/proc/${target_pid}/stat" 2>/dev/null |
        tr -d '\r\n' || true
    )"
    target_proc_fields="${target_proc_stat##*) }"
    read -r -a proc_fields <<<"$target_proc_fields"
    current_proc_start_ticks="${proc_fields[19]:-}"
    current_utime_ticks="${proc_fields[11]:-}"
    current_stime_ticks="${proc_fields[12]:-}"
    if [[ "$current_proc_start_ticks" == "$target_proc_start_ticks" ]]; then
      target_pid_identity_match=1
    fi

    if ((target_pid_identity_match == 1)); then
      process_status="$(
        $adb_bin -s "$serial" shell cat "/proc/${target_pid}/status" \
          2>/dev/null | tr -d '\r' || true
      )"
      vmrss_kb="$(awk '$1 == "VmRSS:" { print $2; exit }' <<<"$process_status")"
      vmswap_kb="$(awk '$1 == "VmSwap:" { print $2; exit }' <<<"$process_status")"
      threads="$(awk '$1 == "Threads:" { print $2; exit }' <<<"$process_status")"
      if [[ "$vmrss_kb" =~ ^[0-9]+$ ]]; then vmrss_available=1; else vmrss_kb='NA'; fi
      if [[ "$vmswap_kb" =~ ^[0-9]+$ ]]; then vmswap_available=1; else vmswap_kb='NA'; fi
      if [[ "$threads" =~ ^[0-9]+$ ]]; then threads_available=1; else threads='NA'; fi

      meminfo_output="$(
        $adb_bin -s "$serial" shell dumpsys meminfo "$target_pid" \
          2>/dev/null | tr -d '\r' || true
      )"
      pss_kb="$(parse_total_pss_kb <<<"$meminfo_output")"
      if [[ "$pss_kb" =~ ^[0-9]+$ ]]; then pss_available=1; else pss_kb='NA'; fi

      if [[ "$current_utime_ticks" =~ ^[0-9]+$ &&
            "$current_stime_ticks" =~ ^[0-9]+$ ]]; then
        cpu_total_ticks=$((current_utime_ticks + current_stime_ticks))
        if [[ "$previous_cpu_ticks" =~ ^[0-9]+$ &&
              "$previous_cpu_epoch" =~ ^[0-9]+$ &&
              "$device_clk_tck" =~ ^[1-9][0-9]*$ ]]; then
          cpu_delta_ticks=$((cpu_total_ticks - previous_cpu_ticks))
          cpu_delta_elapsed_s=$((now_epoch - previous_cpu_epoch))
          if ((cpu_delta_ticks >= 0 && cpu_delta_elapsed_s > 0)); then
            cpu_percent_one_core="$(
              awk -v ticks="$cpu_delta_ticks" \
                -v seconds="$cpu_delta_elapsed_s" \
                -v hz="$device_clk_tck" \
                'BEGIN { printf "%.6f", 100.0 * ticks / (seconds * hz) }'
            )"
            cpu_available=1
          fi
        fi
        previous_cpu_ticks="$cpu_total_ticks"
        previous_cpu_epoch="$now_epoch"
      else
        previous_cpu_ticks=''
        previous_cpu_epoch=''
      fi
    else
      previous_cpu_ticks=''
      previous_cpu_epoch=''
    fi
  else
    previous_cpu_ticks=''
    previous_cpu_epoch=''
  fi

  appops_output="$(
    $adb_bin -s "$serial" shell cmd appops get "$PERFETTO_PACKAGE" \
      RECORD_AUDIO 2>/dev/null | tr -d '\r' || true
  )"
  if grep -Fq 'running=true' <<<"$appops_output"; then
    record_audio_running=1
  elif grep -Fq 'running=false' <<<"$appops_output"; then
    record_audio_running=0
  else
    record_audio_running='NA'
  fi

  services_output="$(
    $adb_bin -s "$serial" shell dumpsys activity services \
      "$PERFETTO_PACKAGE" 2>/dev/null | tr -d '\r' || true
  )"
  if grep -Fq 'isForeground=true' <<<"$services_output"; then
    foreground_service=1
  elif [[ -n "$services_output" ]]; then
    foreground_service=0
  else
    foreground_service='NA'
  fi

  battery_output="$(
    $adb_bin -s "$serial" shell dumpsys battery 2>/dev/null | tr -d '\r' || true
  )"
  battery_level="$(
    awk -F: 'tolower($1) ~ /^[[:space:]]*level$/ {
      gsub(/[[:space:]]/, "", $2); print $2; exit
    }' <<<"$battery_output"
  )"
  battery_temp_decic="$(
    awk -F: 'tolower($1) ~ /^[[:space:]]*temperature$/ {
      gsub(/[[:space:]]/, "", $2); print $2; exit
    }' <<<"$battery_output"
  )"
  charge_counter_uah="$(
    awk -F: 'tolower($1) ~ /^[[:space:]]*charge counter$/ {
      gsub(/[[:space:]]/, "", $2); print $2; exit
    }' <<<"$battery_output"
  )"
  usb_powered="$(
    awk -F: 'tolower($1) ~ /^[[:space:]]*usb powered$/ {
      gsub(/[[:space:]]/, "", $2); print tolower($2); exit
    }' <<<"$battery_output"
  )"
  if [[ "$battery_level" =~ ^[0-9]+$ ]]; then battery_level_available=1; else battery_level='NA'; battery_level_available=0; fi
  if [[ "$battery_temp_decic" =~ ^-?[0-9]+$ ]]; then battery_temp_available=1; else battery_temp_decic='NA'; battery_temp_available=0; fi
  if [[ "$charge_counter_uah" =~ ^-?[0-9]+$ ]]; then charge_counter_available=1; else charge_counter_uah='NA'; charge_counter_available=0; fi
  if [[ "$usb_powered" == 'true' || "$usb_powered" == 'false' ]]; then usb_powered_available=1; else usb_powered='NA'; usb_powered_available=0; fi

  thermal_output="$(
    $adb_bin -s "$serial" shell dumpsys thermalservice 2>/dev/null |
      tr -d '\r' || true
  )"
  thermal_status="$(
    awk -F: '/Thermal Status:/ {
      gsub(/[[:space:]]/, "", $2); print $2; exit
    }' <<<"$thermal_output"
  )"
  skin_temp_c="$(thermal_max_c skin <<<"$thermal_output")"
  cpu_soc_temp_c="$(thermal_max_c cpu_soc <<<"$thermal_output")"
  if [[ "$thermal_status" =~ ^[0-9]+$ ]]; then thermal_status_available=1; else thermal_status='NA'; thermal_status_available=0; fi
  if [[ "$skin_temp_c" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then skin_temp_available=1; else skin_temp_c='NA'; skin_temp_available=0; fi
  if [[ "$cpu_soc_temp_c" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then cpu_soc_temp_available=1; else cpu_soc_temp_c='NA'; cpu_soc_temp_available=0; fi

  printf '%s,%d,%s,%d,%d,%s,%d,%s,%d,%s,%d,%s,%d,%s,%s,%s,%s,%d,%s,%s,%s,%d,%s,%d,%s,%d,%s,%d,%s,%d,%s,%d,%s,%d\n' \
    "$now_utc" "$elapsed_seconds" "${current_pids_csv:-none}" \
    "$target_pid_alive" "$target_pid_identity_match" \
    "$vmrss_kb" "$vmrss_available" "$vmswap_kb" "$vmswap_available" \
    "$pss_kb" "$pss_available" "$threads" "$threads_available" \
    "$cpu_total_ticks" "$cpu_delta_ticks" "$cpu_delta_elapsed_s" \
    "$cpu_percent_one_core" "$cpu_available" \
    "$record_audio_running" "$foreground_service" \
    "$battery_level" "$battery_level_available" \
    "$battery_temp_decic" "$battery_temp_available" \
    "$charge_counter_uah" "$charge_counter_available" \
    "$usb_powered" "$usb_powered_available" \
    "$thermal_status" "$thermal_status_available" \
    "$skin_temp_c" "$skin_temp_available" \
    "$cpu_soc_temp_c" "$cpu_soc_temp_available" >>"$samples_file"

  if ((sample < final_sample)); then
    sleep "$interval_seconds"
  fi
done

ended_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
{
  printf '%s\n' \
    "capture_id=${capture_id}" \
    "package=${PERFETTO_PACKAGE}" \
    "serial=${serial}" \
    "target_uid=${target_uid}" \
    "target_pid=${target_pid}" \
    "target_proc_start_ticks=${target_proc_start_ticks}" \
    "device_clk_tck=${device_clk_tck}" \
    "started_utc=${started_utc}" \
    "ended_utc=${ended_utc}" \
    'planned_duration_seconds=600' \
    'planned_sample_count=11'

  awk -F, '
    function numeric(value) {
      return value ~ /^-?[0-9]+([.][0-9]+)?$/
    }
    NR == 1 {
      for (column = 1; column <= NF; column++) header[$column] = column
      next
    }
    {
      rows++
      elapsed[rows] = $(header["elapsed_s"])
      cpu_available[rows] = $(header["cpu_available"])
      cpu_percent[rows] = $(header["cpu_percent_one_core"])
      cpu_seconds[rows] = $(header["cpu_delta_elapsed_s"])
      pss_available[rows] = $(header["pss_available"])
      pss[rows] = $(header["pss_kb"])
      rss_available[rows] = $(header["vmrss_available"])
      rss[rows] = $(header["vmrss_kb"])
      swap_available[rows] = $(header["vmswap_available"])
      swap[rows] = $(header["vmswap_kb"])
      skin_available[rows] = $(header["skin_temp_available"])
      skin[rows] = $(header["skin_temp_c"])
      cpu_temp_available[rows] = $(header["cpu_soc_temp_available"])
      cpu_temp[rows] = $(header["cpu_soc_temp_c"])
      status_available[rows] = $(header["thermal_status_available"])
      thermal_status[rows] = $(header["thermal_status"])
      charge_available[rows] = $(header["charge_counter_available"])
      charge[rows] = $(header["charge_counter_uah"])
      usb_available[rows] = $(header["usb_powered_available"])
      usb[rows] = $(header["usb_powered"])
    }
    END {
      window_start = rows > 5 ? rows - 5 : 1
      printf "observed_sample_count=%d\n", rows
      printf "observed_elapsed_seconds=%s\n", rows ? elapsed[rows] : "NA"
      printf "last_5m_actual_seconds=%s\n", rows > 1 ? elapsed[rows] - elapsed[window_start] : "NA"

      for (index = 1; index <= rows; index++) {
        if (cpu_available[index] == 1 && numeric(cpu_percent[index]) &&
            numeric(cpu_seconds[index]) && cpu_seconds[index] > 0) {
          cpu_weighted += cpu_percent[index] * cpu_seconds[index]
          cpu_elapsed += cpu_seconds[index]
          cpu_samples++
          if (index > window_start) {
            cpu_last_weighted += cpu_percent[index] * cpu_seconds[index]
            cpu_last_elapsed += cpu_seconds[index]
            cpu_last_samples++
          }
        }
        if (pss_available[index] == 1 && numeric(pss[index])) {
          if (!pss_samples) pss_first = pss[index]
          pss_final = pss[index]
          if (!pss_samples || pss[index] > pss_max) pss_max = pss[index]
          pss_samples++
        }
        if (rss_available[index] == 1 && numeric(rss[index])) {
          rss_final = rss[index]
          if (!rss_samples || rss[index] > rss_max) rss_max = rss[index]
          rss_samples++
        }
        if (swap_available[index] == 1 && numeric(swap[index])) {
          swap_final = swap[index]
          if (!swap_samples || swap[index] > swap_max) swap_max = swap[index]
          swap_samples++
        }
        if (status_available[index] == 1 && numeric(thermal_status[index])) {
          if (!status_samples || thermal_status[index] > status_max) {
            status_max = thermal_status[index]
          }
          status_samples++
        }
        if (usb_available[index] == 1) {
          usb_samples++
          if (usb[index] == "true") usb_powered_seen = 1
        }
      }

      for (index = window_start; index <= rows; index++) {
        if (pss_available[index] == 1 && numeric(pss[index])) {
          if (!pss_window_samples) pss_window_first = pss[index]
          if (pss_window_samples && pss[index] <= pss_window_previous) {
            pss_strictly_increasing = 0
          }
          if (!pss_window_samples) pss_strictly_increasing = 1
          pss_window_previous = pss[index]
          pss_window_final = pss[index]
          pss_window_samples++
        }
        if (skin_available[index] == 1 && numeric(skin[index])) {
          if (!skin_window_samples) skin_window_first = skin[index]
          skin_window_final = skin[index]
          skin_window_samples++
        }
        if (cpu_temp_available[index] == 1 && numeric(cpu_temp[index])) {
          if (!cpu_temp_window_samples) cpu_temp_window_first = cpu_temp[index]
          cpu_temp_window_final = cpu_temp[index]
          cpu_temp_window_samples++
        }
        if (charge_available[index] == 1 && numeric(charge[index])) {
          if (!charge_window_samples) charge_window_first = charge[index]
          charge_window_final = charge[index]
          charge_window_samples++
        }
      }

      printf "cpu_sample_count=%d\n", cpu_samples
      if (cpu_elapsed > 0) printf "cpu_mean_one_core_percent=%.6f\n", cpu_weighted / cpu_elapsed
      else print "cpu_mean_one_core_percent=NA"
      printf "cpu_last_5m_sample_count=%d\n", cpu_last_samples
      if (cpu_last_elapsed > 0) printf "cpu_last_5m_mean_one_core_percent=%.6f\n", cpu_last_weighted / cpu_last_elapsed
      else print "cpu_last_5m_mean_one_core_percent=NA"

      printf "pss_sample_count=%d\n", pss_samples
      if (pss_samples) {
        printf "pss_first_kb=%.0f\npss_final_kb=%.0f\npss_delta_kb=%.0f\npss_max_kb=%.0f\n", pss_first, pss_final, pss_final - pss_first, pss_max
      } else {
        print "pss_first_kb=NA\npss_final_kb=NA\npss_delta_kb=NA\npss_max_kb=NA"
      }
      printf "pss_last_5m_sample_count=%d\n", pss_window_samples
      if (pss_window_samples >= 2) printf "pss_last_5m_delta_kb=%.0f\n", pss_window_final - pss_window_first
      else print "pss_last_5m_delta_kb=NA"
      if (pss_window_samples == 6) printf "pss_positive_monotonic_five_cycles=%d\n", pss_strictly_increasing
      else print "pss_positive_monotonic_five_cycles=NA"

      printf "rss_sample_count=%d\n", rss_samples
      if (rss_samples) printf "rss_final_kb=%.0f\nrss_max_kb=%.0f\n", rss_final, rss_max
      else print "rss_final_kb=NA\nrss_max_kb=NA"
      printf "swap_sample_count=%d\n", swap_samples
      if (swap_samples) printf "swap_final_kb=%.0f\nswap_max_kb=%.0f\n", swap_final, swap_max
      else print "swap_final_kb=NA\nswap_max_kb=NA"

      printf "thermal_status_sample_count=%d\n", status_samples
      if (status_samples) {
        printf "thermal_status_max=%d\n", status_max
        printf "thermal_status_gate=%s\n", status_max >= 3 ? "FAIL" : "PASS"
      } else {
        print "thermal_status_max=NA\nthermal_status_gate=PENDING"
      }
      printf "skin_last_5m_sample_count=%d\n", skin_window_samples
      if (skin_window_samples >= 2) {
        skin_delta = skin_window_final - skin_window_first
        printf "skin_last_5m_delta_c=%.3f\n", skin_delta
        printf "skin_last_5m_slope_gate=%s\n", skin_delta <= 0.5 ? "PASS" : "FAIL"
      } else {
        print "skin_last_5m_delta_c=NA\nskin_last_5m_slope_gate=PENDING"
      }
      printf "cpu_soc_last_5m_sample_count=%d\n", cpu_temp_window_samples
      if (cpu_temp_window_samples >= 2) printf "cpu_soc_last_5m_delta_c=%.3f\n", cpu_temp_window_final - cpu_temp_window_first
      else print "cpu_soc_last_5m_delta_c=NA"

      printf "charge_counter_last_5m_sample_count=%d\n", charge_window_samples
      if (charge_window_samples >= 2) printf "charge_counter_last_5m_delta_uah=%.0f\n", charge_window_final - charge_window_first
      else print "charge_counter_last_5m_delta_uah=NA"
      if (!usb_samples) print "usb_powered_observed=NA"
      else printf "usb_powered_observed=%s\n", usb_powered_seen ? "true" : "false"
    }
  ' "$samples_file"

  printf '%s\n' \
    'cpu_gate=PENDING' \
    'cpu_gate_reason=missing_idle_pre_voice_baseline_with_same_60s_cadence' \
    'pss_gate=PENDING' \
    'pss_gate_reason=missing_idle_pre_voice_baseline_for_final_pss_threshold' \
    'battery_consumption_gate=PENDING' \
    'battery_consumption_gate_reason=missing_equivalent_unplugged_idle_baseline' \
    't061_gate=PENDING' \
    't061_gate_reason=requires_physical_samples_plus_comparable_idle_phone_server_baselines'
} >"$summary_file"

trace_sha256="$(perfetto_metadata_value "$capture_metadata" trace_sha256 || true)"
printf '%s\n' \
  "capture_id=${capture_id}" \
  "package=${PERFETTO_PACKAGE}" \
  "serial=${serial}" \
  "target_uid=${target_uid}" \
  "target_pid=${target_pid}" \
  "target_proc_start_ticks=${target_proc_start_ticks}" \
  "device_clk_tck=${device_clk_tck}" \
  "started_utc=${started_utc}" \
  "ended_utc=${ended_utc}" \
  'planned_duration_seconds=600' \
  'planned_sample_count=11' \
  "trace_sha256=${trace_sha256:-pending_at_observation_end}" \
  "samples_sha256=$(sha256sum "$samples_file" | awk '{print $1}')" \
  "summary_sha256=$(sha256sum "$summary_file" | awk '{print $1}')" \
  'scope=exact_capture_pid plus device-global battery and thermal context' \
  'baseline_gate=PENDING' \
  >"$observation_metadata"

printf '%s\n' \
  "Observacion post-Exit completada: ${samples_file}" \
  "Resumen acotado: ${summary_file}" \
  'T061 sigue PENDING hasta comparar con baselines fisicos equivalentes.'
