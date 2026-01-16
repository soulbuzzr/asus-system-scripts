#!/bin/bash
set -u
set -o pipefail

# ================= REQUIRED ENV =================
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN is not set}"
: "${TG_CHAT_ID:?TG_CHAT_ID is not set}"

HOSTNAME="💻  ASUS Linux Workstation"
LOG_FILE="/var/log/system_dust_cooling_alerts.log"

# ================= LOAD CONFIG =================
CONFIG_FILE="/home/sughosha/System_Scripts/system_health_monitor.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ================= FLOAT HELPERS =================
float_gt() { awk "BEGIN{exit !($1 >  $2)}"; }
float_lt() { awk "BEGIN{exit !($1 <  $2)}"; }

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

cpu_temp() {
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    awk '{printf "%d",$1/1000; exit}' "$z"
  done
}

cpu_active() {
  mpstat 1 1 | awk '/Average/ {printf "%.1f",100-$NF}'
}

# ================= STARTUP =================
log "Dust / cooling monitor started"
tg_send "🧹 *Dust / Cooling Monitor Started*
Host: $HOSTNAME
Thresholds:
• CPU < ${DUST_CPU_ACTIVE_MAX}%
• Temp > ${DUST_CPU_TEMP_MIN}°C
• Duration: ${DUST_DETECT_DURATION}s"

# ================= MAIN LOOP =================
DUST_TIMER=0

while true; do
  CPU_NOW=$(cpu_active)
  TEMP_NOW=$(cpu_temp)

  log "CHECK cpu=${CPU_NOW}% temp=${TEMP_NOW}C timer=${DUST_TIMER}s"

  if float_lt "$CPU_NOW" "$DUST_CPU_ACTIVE_MAX" && \
     float_gt "$TEMP_NOW" "$DUST_CPU_TEMP_MIN"; then
    DUST_TIMER=$((DUST_TIMER + 60))
  else
    DUST_TIMER=0
  fi

  if [ "$DUST_TIMER" -ge "$DUST_DETECT_DURATION" ]; then
    MSG="🧹 *POSSIBLE DUST / COOLING ISSUE*
Host: $HOSTNAME
CPU Active: ${CPU_NOW}%
CPU Temp: ${TEMP_NOW}°C
Duration: ${DUST_DETECT_DURATION}s

*Suggestion:*
- Clean fan and vents
- Check airflow"

    log "$MSG"
    tg_send "$MSG"
    DUST_TIMER=0
  fi

  sleep 60
done
