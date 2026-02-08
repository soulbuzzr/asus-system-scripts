#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${TG_HOURLY_BOT_TOKEN:?Missing TG_HOURLY_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"
: "${HOST_NAME:?Missing HOST_NAME}"

command -v mpstat >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
wait_for_network HOURLY

# ================= BASICS =================
TS="$(date '+%Y-%m-%d %H:%M:%S')"
UPTIME="$(uptime -p | sed 's/^up //')"

# ================= EMOJI HELPERS =================
health_emoji() {
  if [ "$1" -ge 80 ]; then echo "🟢"
  elif [ "$1" -ge 70 ]; then echo "🟡"
  else echo "🔴"; fi
}

temp_emoji() {
  if [ "$1" -lt 60 ]; then echo "🟢"
  elif [ "$1" -lt 70 ]; then echo "🟡"
  else echo "🔴"; fi
}

cpu_emoji() {
  if [ "$1" -lt 20 ]; then echo "🟢"
  elif [ "$1" -lt 60 ]; then echo "🟡"
  else echo "🔴"; fi
}

# ================= CPU METRICS =================
read CPU_US CPU_SY CPU_NI CPU_ID CPU_WA CPU_HI CPU_SI CPU_ST <<< \
$(top -bn1 | awk '/Cpu\(s\)/ {print $2,$4,$6,$8,$10,$12,$14,$16}')

CPU_ACTIVE=$(mpstat 1 60 | awk '/Average/ {printf "%.2f",100-$NF}')
CPU_INT=${CPU_ACTIVE%.*}
CPU_E=$(cpu_emoji "$CPU_INT")

CPU_BLOCK="🧮 *CPU*
    • Active CPU Usage (1 min avg): *$CPU_ACTIVE%* *$CPU_E*
    Live CPU Usage stats:
    • Applications (User): $CPU_US%
    • Kernel / OS (System): $CPU_SY%
    • Low-priority Tasks: $CPU_NI%
    • Idle (Free): $CPU_ID%
    • Waiting for Disk / IO: $CPU_WA%
    • Hardware Interrupts: $CPU_HI%
    • Software Interrupts: $CPU_SI%
    • Virtualization Steal Time: $CPU_ST%

"

# ================= NVME BLOCK =================
for DEV in $(get_nvme_devices); do
  NAME="$(ssd_friendly_name "$DEV")"
  [[ -n "$NAME" ]] || continue

  TEMP="$(ssd_temperature "$DEV")"
  HEALTH="$(ssd_health_percent "$DEV")"
  REALLOC="$(ssd_spare_used "$DEV")"

  [[ -n "$TEMP" && -n "$HEALTH" ]] || continue

  TEMP_E=$(temp_emoji "$TEMP")
  HEALTH_E=$(health_emoji "$HEALTH")

  NVME_BLOCK+="📀 *$NAME*
    • 🌡️ Temp: *$TEMP°C* *$TEMP_E*
    • ❤️ Health: *$HEALTH%* *$HEALTH_E*
    • ♻️ Reallocated blocks: *$REALLOC*

"
done
# ================= GPU BLOCK =================
GPU_BLOCK=""

if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_TEMP="$(read_gpu_temp || true)"
  if [[ "$GPU_TEMP" =~ ^[0-9]+$ ]]; then
    GPU_E=$(temp_emoji "$GPU_TEMP")
    GPU_BLOCK="🎮 *GPU*
• NVIDIA Temp: *${GPU_TEMP}°C* ${GPU_E}

"
  fi
fi

# ================= MEMORY BLOCK =================
read RAM_USED RAM_PCT RAM_AVAIL RAM_TOTAL <<< \
$(free -h | awk '/Mem:/ {printf "%s %.0f %s %s",$3,$3/$2*100,$7,$2}')

SWAP_AVAIL="$(free -h | awk '/Swap:/ {print $4}')"

MEM_BLOCK="🧠 *Memory*
• Used: *${RAM_USED}* (${RAM_PCT}%)
• Available: ${RAM_AVAIL}
• Total: ${RAM_TOTAL}

💾 *Swap*
• Available: ${SWAP_AVAIL}"

# ================= FINAL MESSAGE =================
MSG="*${HOST_NAME}*

⏱ *Uptime*
${UPTIME}

${CPU_BLOCK}${NVME_BLOCK}${GPU_BLOCK}${MEM_BLOCK}

🕒 *${TS}*"

# ================= SEND =================
log HOURLY "sending hourly system health report"
tg_send_hourly "$MSG"
