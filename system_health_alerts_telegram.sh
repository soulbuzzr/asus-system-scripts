#!/bin/bash
set -u
set -o pipefail

# ================= REQUIRED ENV =================
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID is not set}"

HOSTNAME='💻  ASUS Linux Workstation'
LOG_FILE="/var/log/system_health_alerts.log"

# ================= LOAD CONFIG =================
CONFIG_FILE="/home/sughosha/System_Scripts/system_health_monitor.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck source
source "$CONFIG_FILE"

# ================= HELPERS =================
log() {
  echo "$(date '+%F %T') $1" >> "$LOG_FILE"
}

tg_send() {
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    -d text="$1" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true >/dev/null
}

# ================= STARTUP NOTIFY =================
startup_notify() {
  MSG="✅ *SYSTEM MONITOR STARTED*
Host: $HOSTNAME
Monitoring:
- CPU avg (1 min)
- SSD temp (5 sec)
- SSD health (5 min)
- Battery health (wear)
- Battery charge level
Time: $(date '+%F %T')"

  log "System monitor started"
  tg_send "$MSG"
}

# ================= CPU TEMP =================
cpu_temp() {
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    awk '{printf "%d",$1/1000; exit}' "$z"
  done
}

# ================= SSD NAME MAP =================
declare -A SSD_NAME

for DEVN in /dev/nvme0n1 /dev/nvme1n1; do
  [ -e "$DEVN" ] || continue
  CTRL="/dev/$(basename "$DEVN" | sed 's/n1//')"

  SSD_NAME["$CTRL"]=$(smartctl -a "$DEVN" | awk '
    /Model Number/ && /PM9A1/       {print "Samsung PCIe Gen4 SSD"}
    /Model Number/ && /CT500P3SSD8/ {print "Crucial PCIe Gen3 SSD"}
  ')
done

# ================= SSD THRESHOLD MAPPER =================
get_health_thresholds() {
  case "$1" in
    *Samsung*) echo "$SSD_SAMSUNG_HEALTH_WARN $SSD_SAMSUNG_HEALTH_CRIT" ;;
    *Crucial*) echo "$SSD_CRUCIAL_HEALTH_WARN $SSD_CRUCIAL_HEALTH_CRIT" ;;
    *)         echo "95 80" ;;
  esac
}

# ================= CPU CHECK (1 MIN AVG) =================
cpu_check() {
  CPU_AVG=$(mpstat 1 60 | awk '/Average/ {printf "%d",100-$NF}')
  log "CPU_AVG_1MIN=${CPU_AVG}%"

  if [ "$CPU_AVG" -ge "$CPU_ACTIVE_THRESHOLD" ]; then
    TEMP=$(cpu_temp || echo "N/A")

    MSG="🚨 *CPU ALERT*
Host: $HOSTNAME
1-min Avg CPU: ${CPU_AVG}%
CPU Temp: ${TEMP}°C"

    log "$MSG"
    tg_send "$MSG"
  fi
}

# ================= SSD TEMP CHECK (5 SEC) =================
ssd_temp_check() {
  for DEV in /dev/nvme0 /dev/nvme1; do
    [ -e "$DEV" ] || continue
    NAME="${SSD_NAME[$DEV]:-$DEV}"

    TEMP=$(nvme smart-log "$DEV" | awk -F'[(:]' '/^temperature/ {print $2+0}')
    log "SSD_TEMP [$NAME]: ${TEMP}C"

    if [ "$TEMP" -gt "$SSD_TEMP_WARN" ]; then
      MSG="⚠️ *SSD TEMP HIGH*
$NAME
Temperature: ${TEMP}°C"

      log "$MSG"
      tg_send "$MSG"
    fi
  done
}

# ================= SSD HEALTH CHECK (5 MIN) =================
ssd_health_check() {
  for DEV in /dev/nvme0 /dev/nvme1; do
    [ -e "$DEV" ] || continue
    NAME="${SSD_NAME[$DEV]:-$DEV}"

    read WARN CRIT <<< "$(get_health_thresholds "$NAME")"

    HEALTH=$(nvme smart-log "$DEV" | awk -F'[:%]' '/^percentage_used/ {print 100-$2}')
    REALLOC=$(nvme smart-log "$DEV" | awk -F'[:%]' '/^available_spare/&&!/_threshold/ {print 100-$2}')

    log "SSD_HEALTH [$NAME]: health=${HEALTH}% realloc=${REALLOC}%"

    if [ "$HEALTH" -lt "$WARN" ] && [ "$HEALTH" -ge "$CRIT" ]; then
      MSG="🟡 *SSD HEALTH DEGRADED*
$NAME
Health Remaining: ${HEALTH}%"
      log "$MSG"
      tg_send "$MSG"
    fi

    if [ "$HEALTH" -lt "$CRIT" ]; then
      MSG="🔴 *CRITICAL SSD HEALTH*
$NAME
Health Remaining: ${HEALTH}%"
      log "$MSG"
      tg_send "$MSG"
    fi

    if [ "$REALLOC" -gt 0 ]; then
      MSG="🚨 *SSD FAILED BLOCKS*
$NAME
Reallocated: ${REALLOC}%"
      log "$MSG"
      tg_send "$MSG"
    fi
  done
}

# ================= BATTERY HELPERS =================
battery_path() {
  ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1
}

battery_present() {
  [ -n "$(battery_path)" ]
}

battery_health_percent() {
  local full design

  full=$(cat "$(battery_path)/charge_full" 2>/dev/null) || return
  design=$(cat "$(battery_path)/charge_full_design" 2>/dev/null) || return

  # Sanity check
  [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ] || return

  # Integer math (no floats, no awk)
  echo $(( full * 100 / design ))
}

battery_charge_percent() {
  cat "$(battery_path)/capacity" 2>/dev/null
}

# ================= BATTERY HEALTH CHECK =================
battery_health_check() {
  battery_present || return

  HEALTH=$(battery_health_percent)
  [ -n "$HEALTH" ] || return

  log "BATTERY_HEALTH=${HEALTH}%"

  if [ "$HEALTH" -le "$BATTERY_HEALTH_CRIT" ]; then
    MSG="🔴 *BATTERY HEALTH CRITICAL*
Host: $HOSTNAME
Battery Health: ${HEALTH}%"

    log "$MSG"
    tg_send "$MSG"

  elif [ "$HEALTH" -le "$BATTERY_HEALTH_WARN" ]; then
    MSG="🟡 *BATTERY HEALTH DEGRADED*
Host: $HOSTNAME
Battery Health: ${HEALTH}%"

    log "$MSG"
    tg_send "$MSG"
  fi
}

# ================= BATTERY CHARGE CHECK =================
battery_charge_check() {
  battery_present || return

  CHARGE=$(battery_charge_percent)
  [ -n "$CHARGE" ] || return

  log "BATTERY_CHARGE=${CHARGE}%"

  if [ "$CHARGE" -le "$BATTERY_CHARGE_CRIT" ]; then
    MSG="🔴 *BATTERY CHARGE CRITICAL*
Host: $HOSTNAME
Charge Level: ${CHARGE}%"

    log "$MSG"
    tg_send "$MSG"

  elif [ "$CHARGE" -le "$BATTERY_CHARGE_WARN" ]; then
    MSG="🟡 *BATTERY CHARGE LOW*
Host: $HOSTNAME
Charge Level: ${CHARGE}%"

    log "$MSG"
    tg_send "$MSG"
  fi
}

# ================= CONNECTIVITY CHECK =================
internet_up() {
  ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

# ================= MAIN LOOP =================

until internet_up; do
  log "Waiting for internet before startup notify..."
  sleep 5
done

log "Internet is up, sending startup notify..."
startup_notify

CPU_TIMER=0
SSD_HEALTH_TIMER=0
BATTERY_HEALTH_TIMER=0
BATTERY_CHARGE_TIMER=0

while true; do
  ssd_temp_check

  if (( CPU_TIMER >= 60 )); then
    cpu_check
    CPU_TIMER=0
  fi

  if (( SSD_HEALTH_TIMER >= 300 )); then
    ssd_health_check
    SSD_HEALTH_TIMER=0
  fi

  if (( BATTERY_HEALTH_TIMER >= BATTERY_HEALTH_INTERVAL )); then
    battery_health_check
    BATTERY_HEALTH_TIMER=0
  fi

  if (( BATTERY_CHARGE_TIMER >= BATTERY_CHECK_INTERVAL )); then
    battery_charge_check
    BATTERY_CHARGE_TIMER=0
  fi

  sleep 5
  CPU_TIMER=$((CPU_TIMER + 5))
  SSD_HEALTH_TIMER=$((SSD_HEALTH_TIMER + 5))
  BATTERY_HEALTH_TIMER=$((BATTERY_HEALTH_TIMER + 5))
  BATTERY_CHARGE_TIMER=$((BATTERY_CHARGE_TIMER + 5))
done
