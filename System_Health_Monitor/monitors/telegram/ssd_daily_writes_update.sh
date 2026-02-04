#!/usr/bin/env bash
# SSD Write Report at BOOT (NVMe SMART based)
# Reports writes since LAST BOOT in GB
# Uses SSD MODEL NAME as identity (safe against nvme reordering)

set -u

# ================= RESOLVE HOME DIRECTORY for root user (for cron) =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

# ────────────────────────────────────────────────
# Config files
# ────────────────────────────────────────────────
LIB_MODULE="$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

STATE_DIR="$HOME/System_Scripts"
STATE_FILE="${STATE_DIR}/last_boot.json"

NVME_DEVS=(/dev/nvme0n1 /dev/nvme1n1)

# ────────────────────────────────────────────────
# Load shared Library module
# ────────────────────────────────────────────────
[[ -f "$LIB_MODULE" ]] && source "$LIB_MODULE"
HOST_DISPLAY="${HOST_NAME:-🖥 $(hostname)}"

mkdir -p "$STATE_DIR"

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log SSD DAILY WRITES "Waiting for internet..."
  sleep 5
done

sleep 75
# ────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────
ssd_model_name() {
  smartctl -a "$1" 2>/dev/null | awk -F: '/Model Number/ {print $2}' | xargs
}

ssd_friendly_name() {
  local model="$1"
  case "$model" in
    *PM9A1*) echo "Samsung PCIe Gen4 SSD" ;;
    *CT*P3*) echo "Crucial PCIe Gen3 SSD" ;;
    *)       echo "$model" ;;
  esac
}

get_written_units() {
  smartctl -a "$1" 2>/dev/null |
    awk -F: '/Data Units Written/ {print $2}' |
    awk '{print $1}' |
    tr -d ','
}

is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$1" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
}

# ────────────────────────────────────────────────
# Load previous boot state (MODEL → value)
# ────────────────────────────────────────────────
declare -A PREV
declare -A CURRENT

if [[ -f "$STATE_FILE" ]] && jq . "$STATE_FILE" >/dev/null 2>&1; then
  while IFS="=" read -r model val; do
    if [[ -n "$model" ]] && is_number "$val"; then
      PREV["$model"]="$val"
    fi
  done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$STATE_FILE")
fi

# ────────────────────────────────────────────────
# Compute report
# ────────────────────────────────────────────────
report="*📊 SSD Write Report (since last boot)*
*${HOST_DISPLAY}*
*🕒 $(date)*

"

total_gb=0

for dev in "${NVME_DEVS[@]}"; do
  curr=$(get_written_units "$dev")
  is_number "$curr" || continue

  model=$(ssd_model_name "$dev")
  [[ -n "$model" ]] || continue

  CURRENT["$model"]="$curr"

  prev="${PREV[$model]:-}"
  [[ -n "$prev" ]] || continue

  delta=$((curr - prev))
  (( delta >= 0 )) || continue

  gb=$(awk "BEGIN {printf \"%.2f\", $delta * 512000 / 1000 / 1000 / 1000}")

  name=$(ssd_friendly_name "$model")

  report+="💽 ${name}
Writes since last boot: ${gb} GB

"
  total_gb=$(awk "BEGIN {printf \"%.2f\", $total_gb + $gb}")
done

report+="*📦 Total SSD Writes: ${total_gb} GB*"

# ────────────────────────────────────────────────
# Send Telegram (only if previous data existed)
# ────────────────────────────────────────────────
if [[ ${#PREV[@]} -gt 0 ]]; then
  send_telegram "$report"
fi

# ────────────────────────────────────────────────
# Save current state for next boot (MODEL keys)
# ────────────────────────────────────────────────
tmp=$(mktemp)
echo "{}" > "$tmp"

for model in "${!CURRENT[@]}"; do
  jq --arg key "$model" --argjson val "${CURRENT[$model]}" \
    '. + {($key): $val}' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
done

jq --arg ts "$(date -Is)" '. + {timestamp: $ts}' "$tmp" > "$STATE_FILE"
rm -f "$tmp"
