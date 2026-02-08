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

# ================= WAIT FOR NETWORK =================
wait_for_network BATTERY

# ================= STARTUP =================
startup_notify BATTERY "🔋 *Battery Monitor Started*
$HOST_NAME

Monitoring:
• Battery health (wear)
• Battery charge level

Intervals:
• Health check: *${BATTERY_HEALTH_INTERVAL} min*
• Charge check: *${BATTERY_CHECK_INTERVAL} min*"

# ================= INTERVALS (SECONDS) =================
HEALTH_INTERVAL_SEC=$(( BATTERY_HEALTH_INTERVAL * 60 ))
CHARGE_INTERVAL_SEC=$(( BATTERY_CHECK_INTERVAL * 60 ))

# ================= TIMESTAMPS =================
now=$(date +%s)
LAST_HEALTH_CHECK=$now
LAST_CHARGE_CHECK=$now

# ================= MAIN LOOP =================
while true; do
  now=$(date +%s)

  # -------- Battery presence --------
  if ! battery_present; then
    log BATTERY "No battery detected – exiting"
    tg_send "⚠️ *BATTERY NOT DETECTED*
$HOST_NAME

Battery monitor exiting."
    exit 0
  fi

  # -------- Battery health --------
  if (( now - LAST_HEALTH_CHECK >= HEALTH_INTERVAL_SEC )); then
    HEALTH=$(battery_health_percent || true)
    if [[ -n "$HEALTH" ]]; then
      log BATTERY "health=${HEALTH}%"

      if (( HEALTH <= BATTERY_HEALTH_CRIT )); then
        tg_send "🔴 *BATTERY HEALTH CRITICAL*
$HOST_NAME
Health: *${HEALTH}%*"

      elif (( HEALTH <= BATTERY_HEALTH_WARN )); then
        tg_send "🟡 *BATTERY HEALTH DEGRADED*
$HOST_NAME
Health: *${HEALTH}%*"
      fi
    fi
    LAST_HEALTH_CHECK=$now
  fi

  # -------- Battery charge --------
  if (( now - LAST_CHARGE_CHECK >= CHARGE_INTERVAL_SEC )); then
    CHARGE=$(battery_charge_percent || true)
    if [[ -n "$CHARGE" ]]; then
      log BATTERY "charge=${CHARGE}%"

      if (( CHARGE <= BATTERY_CHARGE_CRIT )); then
        tg_send "🔴 *BATTERY CHARGE CRITICAL*
$HOST_NAME
Charge: *${CHARGE}%*"

      elif (( CHARGE <= BATTERY_CHARGE_WARN )); then
        tg_send "🟡 *BATTERY CHARGE LOW*
$HOST_NAME
Charge: *${CHARGE}%*"
      fi
    fi
    LAST_CHARGE_CHECK=$now
  fi

  sleep 60
done
