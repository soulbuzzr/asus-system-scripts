#!/bin/bash
set -u
set -o pipefail

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${GPU_TEMP_THRESHOLD:?Missing GPU_TEMP_THRESHOLD}"   # °C
: "${HOST_NAME:?Missing HOST_NAME}"

# ================= GPU DETECTION =================
command -v nvidia-smi >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
wait_for_network GPU_TEMP

# ================= STARTUP =================
startup_notify GPU_TEMP "✅ *GPU Temperature Monitor Active*
$HOST_NAME

Monitoring:
• 30-second averaged GPU temperature
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

# ================= TEMP READER =================
read_gpu_temp() {
  nvidia-smi --query-gpu=temperature.gpu \
             --format=csv,noheader,nounits 2>/dev/null
}

# ================= MAIN LOOP =================
while true; do
  AVG_TEMP=$(avg_over_seconds 30 read_gpu_temp) || {
    sleep 1
    continue
  }

  AVG_TEMP_INT=${AVG_TEMP%.*}

  log GPU_TEMP "avg_30sec=${AVG_TEMP}C"

  if (( AVG_TEMP_INT >= GPU_TEMP_THRESHOLD )); then
    tg_send "🔥 *GPU TEMPERATURE ALERT*
$HOST_NAME

30-sec Avg GPU Temp: *${AVG_TEMP}°C*
Threshold: *${GPU_TEMP_THRESHOLD}°C*"

    log GPU_TEMP "ALERT SENT (${AVG_TEMP}C)"
  fi

done
