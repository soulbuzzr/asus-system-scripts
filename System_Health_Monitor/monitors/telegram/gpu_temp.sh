#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${GPU_TEMP_THRESHOLD:?Missing GPU_TEMP_THRESHOLD}"
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= GPU DETECTION =================
command -v nvidia-smi >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log GPU_TEMP "Waiting for internet..."
  sleep 5
done

sleep 60

# ================= STARTUP NOTIFY =================
STARTUP_MSG="✅ *GPU Temperature Monitor Active*
$HOST_NAME
Monitoring: *30-second averaged GPU temperature*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

log GPU_TEMP "GPU temperature monitor started (30s avg, threshold=${GPU_TEMP_THRESHOLD}C)"
tg_send "$STARTUP_MSG"

# ================= TEMP READER =================
read_gpu_temp() {
  nvidia-smi --query-gpu=temperature.gpu \
             --format=csv,noheader,nounits 2>/dev/null
}

# ================= CONTINUOUS MONITOR =================
while true; do
  SUM=0
  COUNT=0

  # Collect 30 samples (1 per second)
  for _ in $(seq 1 30); do
    TEMP=$(read_gpu_temp || echo "")
    if [ -n "$TEMP" ]; then
      SUM=$((SUM + TEMP))
      COUNT=$((COUNT + 1))
    fi
    sleep 1
  done

  # No samples → skip safely
  [ "$COUNT" -eq 0 ] && continue

  # Integer average (comparison)
  AVG_TEMP_INT=$((SUM / COUNT))

  # Float average (display)
  AVG_TEMP_FLOAT=$(awk -v s="$SUM" -v c="$COUNT" \
    'BEGIN { printf "%.2f", s / c }')

  log GPU_TEMP "GPU_TEMP_AVG_30SEC=${AVG_TEMP_FLOAT}C"

  if (( AVG_TEMP_INT >= GPU_TEMP_THRESHOLD )); then
    ALERT_MSG="🔥 *GPU TEMPERATURE ALERT*
$HOST_NAME
30-sec Avg GPU Temp: *${AVG_TEMP_FLOAT}°C*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

    log GPU_TEMP "ALERT SENT (${AVG_TEMP_FLOAT}C)"
    tg_send "$ALERT_MSG"
  fi
done
