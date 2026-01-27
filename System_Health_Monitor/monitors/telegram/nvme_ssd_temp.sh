#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_TEMP_WARN:?Missing SSD_TEMP_WARN}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v nvme >/dev/null 2>&1 || exit 0

# ================= SSD FRIENDLY NAME CACHE =================
declare -A SSD_NAME

get_ssd_name() {
  local dev="$1"

  [ -n "${SSD_NAME[$dev]:-}" ] && {
    echo "${SSD_NAME[$dev]}"
    return
  }

  local model
  model=$(nvme id-ctrl "$dev" 2>/dev/null \
    | awk -F: '/^mn/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')

  SSD_NAME["$dev"]="${model:-$dev}"
  echo "${SSD_NAME[$dev]}"
}

get_ssd_health() {
  nvme smart-log "$1" 2>/dev/null \
    | awk -F'[:%]' '/^percentage_used/ {print 100-$2}'
}

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
  for DEV in /dev/nvme[0-9]; do
    [ -e "$DEV" ] || continue

    NAME=$(get_ssd_name "$DEV")

    TEMP=$(nvme smart-log "$DEV" \
      | awk -F'[(:]' '/^temperature/ {print $2+0}')

    [ -n "$TEMP" ] || continue

    log SSD_TEMP "DRIVE=\"$NAME\" DEV=\"$DEV\" TEMP=${TEMP}C"

    if (( TEMP > SSD_TEMP_WARN )); then
      HEALTH=$(get_ssd_health "$DEV")

      tg_send "⚠️ *SSD TEMP HIGH*
$HOST_NAME
Drive: *$NAME*
Device: \`$DEV\`
Health Remaining: *${HEALTH:-N/A}%*
Temperature: *${TEMP}°C*"

      log SSD_TEMP "ALERT SENT ($NAME $DEV ${TEMP}C health=${HEALTH:-NA})"
    fi
  done

  sleep 5
done
