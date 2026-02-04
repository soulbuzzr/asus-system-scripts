#!/usr/bin/env bash
# SSD Write Report at BOOT (NVMe SMART based)
# Reports writes since LAST BOOT in GB

set -u

# ────────────────────────────────────────────────
# Config files
# ────────────────────────────────────────────────
ENV_FILE="/home/sughosha/System_Scripts/System_Health_Monitor/env/system_health_bot.env"
CONF_FILE="/home/sughosha/System_Scripts/System_Health_Monitor/conf/system_limits.conf"
LIB_MODULE="/home/sughosha/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

STATE_DIR="/home/sughosha/System_Scripts"
STATE_FILE="${STATE_DIR}/last_boot.json"

NVME_DEVS=(/dev/nvme0n1 /dev/nvme1n1)

# ────────────────────────────────────────────────
# Load Telegram env
# ────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || exit 0
source "$ENV_FILE"

: "${TG_BOT_TOKEN:?TG_BOT_TOKEN missing}"
: "${TG_CHAT_ID:?TG_CHAT_ID missing}"

# ────────────────────────────────────────────────
# Load system config (optional)
# ────────────────────────────────────────────────
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
HOST_DISPLAY="${HOST_NAME:-🖥 $(hostname)}"

mkdir -p "$STATE_DIR"

# ────────────────────────────────────────────────
# Load shared Library module
# ────────────────────────────────────────────────
[[ -f "$LIB_MODULE" ]] && source "$LIB_MODULE"

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log SSD DAILY WRITES "Waiting for internet..."
  sleep 5
done

# ────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────
ssd_model_name() {
  smartctl -a "$1" 2>/dev/null | awk -F: '/Model Number/ {print $2}' | xargs
}

ssd_friendly_name() {
  local model
  model=$(ssd_model_name "$1")

  case "$model" in
    *PM9A1*) echo "Samsung PCIe Gen4 SSD" ;;
    *CT*P3*) echo "Crucial PCIe Gen3 SSD" ;;
    *)       echo "${model:-$1}" ;;
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
# Load previous boot state
# ────────────────────────────────────────────────
declare -A PREV
declare -A CURRENT

if [[ -f "$STATE_FILE" ]] && jq . "$STATE_FILE" >/dev/null 2>&1; then
  for dev in "${NVME_DEVS[@]}"; do
    val=$(jq -r ".\"$dev\" // empty" "$STATE_FILE")
    if is_number "$val"; then
      PREV["$dev"]="$val"
    fi
  done
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
  CURRENT["$dev"]="$curr"

  prev="${PREV[$dev]:-}"
  [[ -n "$prev" ]] || continue

  delta=$((curr - prev))
  gb=$(awk "BEGIN {printf \"%.2f\", $delta * 512000 / 1000 / 1000 / 1000}")

  name=$(ssd_friendly_name "$dev")

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
# Save current state for next boot
# ────────────────────────────────────────────────
tmp=$(mktemp)
echo "{}" > "$tmp"

for dev in "${!CURRENT[@]}"; do
  jq --arg dev "$dev" --argjson val "${CURRENT[$dev]}" \
    '. + {($dev): $val}' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
done

jq --arg ts "$(date -Is)" '. + {timestamp: $ts}' "$tmp" > "$STATE_FILE"
rm -f "$tmp"
