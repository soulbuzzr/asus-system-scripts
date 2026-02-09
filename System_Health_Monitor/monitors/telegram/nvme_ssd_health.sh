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

# ================= WAIT FOR NETWORK =================
wait_for_network SSD

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

# ================= STARTUP =================
startup_notify SSD "✅ *NVMe SSD Health Monitor Active*
$HOST_NAME

Monitoring:
• NVMe health percentage
• Spare block usage
Interval: *5 minutes*"

# ================= INTERVAL =================
CHECK_INTERVAL_SEC=300   # 5 minutes

# ================= MAIN LOOP =================
while true; do
  for DEV in $(get_nvme_devices); do
    NAME=$(ssd_friendly_name "$DEV")
    read WARN CRIT <<< "$(get_health_thresholds "$NAME")"

    HEALTH=$(ssd_health_percent "$DEV" || true)
    SPARE_USED=$(ssd_spare_used "$DEV" || true)

    [[ -n "$HEALTH" ]] || continue

    log SSD "[$NAME] health=${HEALTH}% spare_used=${SPARE_USED}%"

    if (( HEALTH < WARN && HEALTH >= CRIT )); then
      tg_send "🟡 *SSD HEALTH DEGRADED*
$HOST_NAME

Drive: *$NAME*
Health Remaining: *${HEALTH}%*
Warning Threshold: *${WARN}%*"
    fi

    if (( HEALTH < CRIT )); then
      tg_send "🔴 *CRITICAL SSD HEALTH*
$HOST_NAME

Drive: *$NAME*
Health Remaining: *${HEALTH}%*
Critical Threshold: *${CRIT}%*"
    fi

    if [[ -n "$SPARE_USED" ]] && (( SPARE_USED > 0 )); then
      tg_send "🚨 *SSD FAILED BLOCKS DETECTED*
$HOST_NAME

Drive: *$NAME*
Spare Used: *${SPARE_USED}%*"
    fi
  done

  sleep 300
done
