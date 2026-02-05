#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_TEMP_WARN:?Missing SSD_TEMP_WARN}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v nvme >/dev/null 2>&1 || exit 0
command -v smartctl >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log SSD_TEMP "Waiting for internet..."
  sleep 5
done

# ================= STARTUP NOTIFY =================
log SSD_TEMP "SSD temperature monitor started"
tg_send "💾 *SSD Temperature Monitor Active*
$HOST_NAME
Threshold: *${SSD_TEMP_WARN}°C*"

# ================= MAIN LOOP =================
while true; do
  for DEV in $(get_nvme_devices); do
    NAME=$(ssd_friendly_name "$DEV")
    TEMP=$(ssd_temperature "$DEV")

    [ -n "$TEMP" ] || continue

    log SSD_TEMP "[$NAME] temp=${TEMP}C"

    if (( TEMP > SSD_TEMP_WARN )); then
      tg_send "⚠️ *SSD TEMP HIGH*
$HOST_NAME
Drive: *$NAME*
Temperature: *${TEMP}°C*
Threshold: *${SSD_TEMP_WARN}°C*"
    fi
  done

  sleep 60
done
