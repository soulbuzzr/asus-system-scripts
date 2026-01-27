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

sleep 60

# ================= NVME DEVICE SCAN =================
get_nvme_devices() {
  smartctl --scan | awk '{print $1}' | grep nvme
}

# ================= FRIENDLY NAME =================
friendly_name() {
  smartctl -a "$1" 2>/dev/null | awk '
    /Model Number/ && /PM9A1/       {print "Samsung PCIe Gen4 SSD"}
    /Model Number/ && /CT.*P3/      {print "Crucial PCIe Gen3 SSD"}
  '
}

# ================= SSD NAME MAP =================
declare -A SSD_NAME

for DEVN in $(get_nvme_devices); do
  CTRL="/dev/$(basename "$DEVN" | sed 's/n[0-9]*$//')"
  NAME=$(friendly_name "$DEVN")
  [ -z "$NAME" ] && continue
  SSD_NAME["$CTRL"]="$NAME"
done

# ================= THRESHOLD MAPPER =================
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
STARTUP_MSG="✅ *NVMe SSD Health Monitor Active*
$HOST_NAME
Monitoring: *NVMe health and spare blocks*
Interval: *5 minutes*"

log SSD "NVMe SSD health monitor started"
tg_send "$STARTUP_MSG"

# ================= CONTINUOUS MONITOR =================
while true; do
  for DEV in "${!SSD_NAME[@]}"; do
    NAME="${SSD_NAME[$DEV]}"

    read WARN CRIT <<< "$(get_health_thresholds "$NAME")"

    HEALTH=$(nvme smart-log "$DEV" \
      | awk -F'[:%]' '/^percentage_used/ {print 100-$2}')

    REALLOC=$(nvme smart-log "$DEV" \
      | awk -F'[:%]' '/^available_spare/&&!/_threshold/ {print 100-$2}')

    log SSD "[$NAME] health=${HEALTH}% spare_loss=${REALLOC}%"

    if (( HEALTH < WARN && HEALTH >= CRIT )); then
      MSG="🟡 *SSD HEALTH DEGRADED*
$HOST_NAME
Drive: $NAME
Health Remaining: *${HEALTH}%*"

      log SSD "DEGRADED: $NAME (${HEALTH}%)"
      tg_send "$MSG"
    fi

    if (( HEALTH < CRIT )); then
      MSG="🔴 *CRITICAL SSD HEALTH*
$HOST_NAME
Drive: $NAME
Health Remaining: *${HEALTH}%*"

      log SSD "CRITICAL: $NAME (${HEALTH}%)"
      tg_send "$MSG"
    fi

    if (( REALLOC > 0 )); then
      MSG="🚨 *SSD FAILED BLOCKS*
$HOST_NAME
Drive: $NAME
Spare Used: *${REALLOC}%*"

      log SSD "FAILED BLOCKS: $NAME (${REALLOC}%)"
      tg_send "$MSG"
    fi
  done

  sleep 300
done
