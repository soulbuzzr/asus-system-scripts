#!/usr/bin/env bash
# SSD Daily Writes Monitor (NVMe SMART based)
# Reports DAILY writes in GB
# Safe for early shutdown

set -u
MODE="${1:-}"

# ────────────────────────────────────────────────
# Config files
# ────────────────────────────────────────────────
ENV_FILE="/home/sughosha/System_Scripts/System_Health_Monitor/env/system_health_bot.env"
CONF_FILE="/home/sughosha/System_Scripts/System_Health_Monitor/conf/system_limits.conf"

STATE_DIR="/var/lib/ssd-daily-write"
BOOT_FILE="${STATE_DIR}/boot.json"

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
# Helpers
# ────────────────────────────────────────────────
ssd_model_name() {
  local dev="$1"
  smartctl -a "$dev" 2>/dev/null | awk -F: '/Model Number/ {print $2}' | xargs
}

ssd_friendly_name() {
  local dev="$1"
  local model

  model=$(ssd_model_name "$dev")

  case "$model" in
    *PM9A1*)
      echo "Samsung PCIe Gen4 SSD"
      ;;
    *CT*P3*)
      echo "Crucial PCIe Gen3 SSD"
      ;;
    *)
      echo "${model:-$dev}"
      ;;
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
# BOOT MODE
# ────────────────────────────────────────────────
if [[ "$MODE" == "boot" ]]; then
  tmp=$(mktemp)
  echo "{}" > "$tmp"

  for dev in "${NVME_DEVS[@]}"; do
    duw=$(get_written_units "$dev")
    is_number "$duw" || continue

    jq --arg dev "$dev" --argjson val "$duw" \
      '. + {($dev): $val}' "$tmp" > "${tmp}.new" &&
      mv "${tmp}.new" "$tmp"
  done

  jq --arg ts "$(date -Is)" '. + {timestamp: $ts}' "$tmp" > "$BOOT_FILE"
  rm -f "$tmp"
  exit 0
fi

# ────────────────────────────────────────────────
# SHUTDOWN MODE
# ────────────────────────────────────────────────
if [[ "$MODE" == "shutdown" ]]; then
  set +e  # never block shutdown

  if ! jq . "$BOOT_FILE" >/dev/null 2>&1; then
    send_telegram "⚠️ SSD write report skipped — baseline missing or corrupted."
    exit 0
  fi

  report="*📊 SSD Daily Write Report*
*${HOST_DISPLAY}*
*🕒 $(date)*

"

  total_gb=0

  for dev in "${NVME_DEVS[@]}"; do
    boot_val=$(jq -r ".\"$dev\" // empty" "$BOOT_FILE")
    shut_val=$(get_written_units "$dev")

    is_number "$boot_val" || continue
    is_number "$shut_val" || continue

    delta=$((shut_val - boot_val))

    gb=$(awk "BEGIN {printf \"%.2f\", $delta * 512000 / 1000 / 1000 / 1000}")

    name=$(ssd_friendly_name "$dev")

    report+="💽 ${name}
  Writes today: ${gb} GB

"
    total_gb=$(awk "BEGIN {printf \"%.2f\", $total_gb + $gb}")
  done

  report+="*📦 Total SSD Writes Today: ${total_gb} GB*"

  send_telegram "$report"
fi
