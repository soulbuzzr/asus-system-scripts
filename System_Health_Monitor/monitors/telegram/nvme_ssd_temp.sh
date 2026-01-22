#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_TEMP_WARN:?Missing SSD_TEMP_WARN}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v nvme >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log SSD_TEMP "Waiting for internet before startup..."
  sleep 5
done

sleep 60

# ================= STARTUP =================
log SSD_TEMP "SSD temperature monitor started"
tg_send "💾 *SSD Temperature Monitor Started*
$HOST_NAME
Alert threshold: *${SSD_TEMP_WARN}°C*"

# ================= MAIN LOOP =================
while true; do
  for DEV in /dev/nvme*; do
    [ -e "$DEV" ] || continue
    [[ "$DEV" =~ n1$ ]] && continue   # skip namespaces

    TEMP=$(nvme smart-log "$DEV" \
      | awk -F'[(:]' '/^temperature/ {print $2+0}')

    [ -n "$TEMP" ] || continue

    log SSD_TEMP "DEVICE=${DEV} TEMP=${TEMP}C"

    if (( TEMP > SSD_TEMP_WARN )); then
      tg_send "⚠️ *SSD TEMP HIGH*
$HOST_NAME
Device: $DEV
Temperature: *${TEMP}°C*"

      log SSD_TEMP "ALERT SENT (${DEV} ${TEMP}C)"
    fi
  done

  sleep 5
done
