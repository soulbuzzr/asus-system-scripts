#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${BATTERY_HEALTH_WARN:?Missing BATTERY_HEALTH_WARN}"
: "${BATTERY_HEALTH_CRIT:?Missing BATTERY_HEALTH_CRIT}"
: "${BATTERY_HEALTH_INTERVAL:?Missing BATTERY_HEALTH_INTERVAL}"
: "${BATTERY_CHARGE_WARN:?Missing BATTERY_CHARGE_WARN}"
: "${BATTERY_CHARGE_CRIT:?Missing BATTERY_CHARGE_CRIT}"
: "${BATTERY_CHECK_INTERVAL:?Missing BATTERY_CHECK_INTERVAL}"
: "${HOST_NAME:?Missing HOST_NAME}"

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

  [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ] || return

  echo $(( full * 100 / design ))
}

battery_charge_percent() {
  cat "$(battery_path)/capacity" 2>/dev/null
}

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log BATTERY "Waiting for internet before startup..."
  sleep 5
done

sleep 60

# ================= STARTUP =================
log BATTERY "Battery monitor started"
tg_send "🔋 *Battery Monitor Started*
$HOST_NAME

Monitoring:
• Battery health (wear)
• Battery charge level"

# ================= TIMERS =================
BATTERY_HEALTH_TIMER=0
BATTERY_CHARGE_TIMER=0

# ================= MAIN LOOP =================
while true; do
  battery_present || sleep 30 && continue

  # -------- Battery health --------
  if (( BATTERY_HEALTH_TIMER >= BATTERY_HEALTH_INTERVAL )); then
    HEALTH=$(battery_health_percent || echo "")
    if [ -n "$HEALTH" ]; then
      log BATTERY "HEALTH=${HEALTH}%"

      if (( HEALTH <= BATTERY_HEALTH_CRIT )); then
        tg_send "🔴 *BATTERY HEALTH CRITICAL*
$HOST_NAME
Battery Health: *${HEALTH}%*"

        log BATTERY "ALERT: health critical (${HEALTH}%)"

      elif (( HEALTH <= BATTERY_HEALTH_WARN )); then
        tg_send "🟡 *BATTERY HEALTH DEGRADED*
$HOST_NAME
Battery Health: *${HEALTH}%*"

        log BATTERY "ALERT: health degraded (${HEALTH}%)"
      fi
    fi
    BATTERY_HEALTH_TIMER=0
  fi

  # -------- Battery charge --------
  if (( BATTERY_CHARGE_TIMER >= BATTERY_CHECK_INTERVAL )); then
    CHARGE=$(battery_charge_percent || echo "")
    if [ -n "$CHARGE" ]; then
      log BATTERY "CHARGE=${CHARGE}%"

      if (( CHARGE <= BATTERY_CHARGE_CRIT )); then
        tg_send "🔴 *BATTERY CHARGE CRITICAL*
$HOST_NAME
Charge Level: *${CHARGE}%*"

        log BATTERY "ALERT: charge critical (${CHARGE}%)"

      elif (( CHARGE <= BATTERY_CHARGE_WARN )); then
        tg_send "🟡 *BATTERY CHARGE LOW*
$HOST_NAME
Charge Level: *${CHARGE}%*"

        log BATTERY "ALERT: charge low (${CHARGE}%)"
      fi
    fi
    BATTERY_CHARGE_TIMER=0
  fi

  sleep 5
  BATTERY_HEALTH_TIMER=$((BATTERY_HEALTH_TIMER + 5))
  BATTERY_CHARGE_TIMER=$((BATTERY_CHARGE_TIMER + 5))
done
