#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${SSD_SAMSUNG_HEALTH_WARN:?Missing SSD_SAMSUNG_HEALTH_WARN}"
: "${SSD_SAMSUNG_HEALTH_CRIT:?Missing SSD_SAMSUNG_HEALTH_CRIT}"
: "${SSD_CRUCIAL_HEALTH_WARN:?Missing SSD_CRUCIAL_HEALTH_WARN}"
: "${SSD_CRUCIAL_HEALTH_CRIT:?Missing SSD_CRUCIAL_HEALTH_CRIT}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v nvme >/dev/null 2>&1 || exit 0
command -v smartctl >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log SSD "Waiting for internet..."
  sleep 5
done

# ================= THRESHOLDS =================
get_health_thresholds() {
  case "$1" in
    *Samsung*)
      echo "$SSD_SAMSUNG_HEALTH_WARN $SSD_SAMSUNG_HEALTH_CRIT"
      ;;
    *Crucial*)
      echo "$SSD_CRUCIAL_HEALTH_WARN $SSD_CRUCIAL_HEALTH_CRIT"
      ;;
    *)
      echo "95 80"
      ;;
  esac
}

# ================= STARTUP NOTIFY =================
log SSD "NVMe SSD health monitor started"
tg_send "✅ *NVMe SSD Health Monitor Active*
$HOST_NAME
Interval: *5 minutes*"

# ================= MAIN LOOP =================
while true; do
  for DEV in $(get_nvme_devices); do
    NAME=$(ssd_friendly_name "$DEV")
    read WARN CRIT <<< "$(get_health_thresholds "$NAME")"

    HEALTH=$(ssd_health_percent "$DEV")
    SPARE_USED=$(ssd_spare_used "$DEV")

    log SSD "[$NAME] health=${HEALTH}% spare_used=${SPARE_USED}%"

    if (( HEALTH < WARN && HEALTH >= CRIT )); then
      tg_send "🟡 *SSD HEALTH DEGRADED*
$HOST_NAME
Drive: *$NAME*
Health Remaining: *${HEALTH}%*
Threshold: *${WARN}%*"
    fi

    if (( HEALTH < CRIT )); then
      tg_send "🔴 *CRITICAL SSD HEALTH*
$HOST_NAME
Drive: *$NAME*
Health Remaining: *${HEALTH}%*
Threshold: *${CRIT}%*"
    fi

    if (( SPARE_USED > 0 )); then
      tg_send "🚨 *SSD FAILED BLOCKS*
$HOST_NAME
Drive: *$NAME*
Spare Used: *${SPARE_USED}%*"
    fi
  done

  sleep 300
done
