#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_TEMP_WARN:?Missing SSD_TEMP_WARN}"   # °C
: "${HOST_NAME:?Missing HOST_NAME}"

command -v nvme >/dev/null 2>&1 || exit 0
command -v smartctl >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
wait_for_network SSD_TEMP

# ================= STARTUP =================
startup_notify SSD_TEMP "💾 *SSD Temperature Monitor Active*
$HOST_NAME

Threshold:
• SSD temperature > *${SSD_TEMP_WARN}°C*
Interval: *1 minute*"

# ================= INTERVAL =================
CHECK_INTERVAL_SEC=60

# ================= MAIN LOOP =================
while true; do
  for DEV in $(get_nvme_devices); do
    NAME=$(ssd_friendly_name "$DEV")
    TEMP=$(ssd_temperature "$DEV" || true)

    [[ -n "$TEMP" ]] || continue

    log SSD_TEMP "[$NAME] temp=${TEMP}C"

    if (( TEMP > SSD_TEMP_WARN )); then
      tg_send "⚠️ *SSD TEMPERATURE HIGH*
$HOST_NAME

Drive: *$NAME*
Temperature: *${TEMP}°C*
Threshold: *${SSD_TEMP_WARN}°C*"
    fi
  done

  sleep 60
done
