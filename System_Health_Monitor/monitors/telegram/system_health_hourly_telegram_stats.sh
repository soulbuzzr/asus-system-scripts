#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

# ================= LOAD ENV =================
ENV_FILE="$HOME/System_Scripts/System_Health_Monitor/env/system_health_bot.env"

if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${TG_HOURLY_BOT_TOKEN:?Missing TG_HOURLY_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

# ================= LOG FILE =================
LOG_DIR="/var/log/system_health"
LOG_FILE="$LOG_DIR/health.log"

mkdir -p "$LOG_DIR"

# ================= BASICS =================
HOST='💻  ASUS Linux Workstation'
TS=$(date '+%Y-%m-%d %H:%M:%S')
UPTIME=$(uptime -p | sed 's/^up //')

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

# extract integer part for emoji logic
CPU_INT=${CPU_ACTIVE%.*}
CPU_E=$(cpu_emoji "$CPU_INT")

# ================= NVIDIA GPU =================
get_nvidia_temp() {
  command -v nvidia-smi >/dev/null 2>&1 || return 1
  nvidia-smi --query-gpu=temperature.gpu \
             --format=csv,noheader,nounits 2>/dev/null | head -n1
}

NVIDIA_BLOCK=""

if GPU_TEMP=$(get_nvidia_temp); then
  if [[ "$GPU_TEMP" =~ ^[0-9]+$ ]]; then
    GPU_E=$(temp_emoji "$GPU_TEMP")
    NVIDIA_BLOCK="🎮 *NVIDIA GPU*
    • 🌡️ Temp: *$GPU_TEMP°C* *$GPU_E*

"
  fi
fi

# ================= NVME DEVICE SCAN =================
get_nvme_devices() {
  smartctl --scan | awk '{print $1}' | grep nvme
}

friendly_name() {
  smartctl -a "$1" 2>/dev/null | awk '
    /Model Number/ && /PM9A1/       {print "Samsung PCIe Gen4 SSD"}
    /Model Number/ && /CT500P3SSD8/ {print "Crucial PCIe Gen3 SSD"}
  '
}

# ================= NVME METRICS =================
nvme_metrics() {
  nvme smart-log "$1" 2>/dev/null | awk -F'[(:%]' '
    /^temperature/ {t=$2}
    /^percentage_used/ {h=100-$2}
    /^available_spare/&&!/_threshold/ {r=100-$2}
    END {printf "%d %d %d",t,h,r}'
}

NVME_BLOCK=""

for DEV in $(get_nvme_devices); do
  NAME=$(friendly_name "$DEV")
  [ -z "$NAME" ] && continue

  CTRL="/dev/$(basename "$DEV" | sed 's/n[0-9]*$//')"
  read TEMP HEALTH REALLOC <<< "$(nvme_metrics "$CTRL")"

  TEMP_E=$(temp_emoji "$TEMP")
  HEALTH_E=$(health_emoji "$HEALTH")

  NVME_BLOCK+="📀 *$NAME*
    • 🌡️ Temp: *$TEMP°C* *$TEMP_E*
    • ❤️ Health: *$HEALTH%* *$HEALTH_E*
    • ♻️ Reallocated blocks: *$REALLOC*
"$'\n'
done

# ================= MEMORY + SWAP =================
read RAM_USED RAM_PCT RAM_AVAIL RAM_TOTAL <<< \
$(free -h | awk '/Mem:/ {printf "%s %.0f %s %s",$3,$3/$2*100,$7,$2}')

read SWAP_AVAIL <<< \
$(free -h | awk '/Swap:/ {print $4}')

# ================= FINAL MESSAGE =================
MSG="*$HOST*

⏱️ *Uptime*
  *$UPTIME*

🧮 *CPU*
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

$NVME_BLOCK$NVIDIA_BLOCK🧠 *Memory*
    • Used: *$RAM_USED* *($RAM_PCT%)*
    • Available: *$RAM_AVAIL*
    • Total: *$RAM_TOTAL*

💾 *Swap*
    • Available: *$SWAP_AVAIL*

🕒 *$TS*"

# ================= LOG =================
echo "$(echo "$MSG" | sed 's/\*//g')" >> "$LOG_FILE"

# ================= TELEGRAM =================
curl -s -X POST "https://api.telegram.org/bot$TG_HOURLY_BOT_TOKEN/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  -d text="$MSG" \
  -d parse_mode=Markdown \
  -d disable_web_page_preview=true >/dev/null
