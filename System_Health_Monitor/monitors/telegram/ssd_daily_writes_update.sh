#!/usr/bin/env bash
# SSD Write Report at BOOT (NVMe SMART based)
# Reports writes since LAST BOOT in GB
# Uses FRIENDLY SSD NAME as identity

set -u
set -o pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

# ================= PATHS =================
BASE_DIR="$HOME/System_Scripts/System_Health_Monitor"
LIB_MODULE="$BASE_DIR/lib/health_lib.sh"

STATE_DIR="$HOME/System_Scripts"
STATE_FILE="${STATE_DIR}/last_boot.json"

NVME_DEVS=(/dev/nvme0n1 /dev/nvme1n1)

# ================= LOAD SHARED LIB =================
[[ -f "$LIB_MODULE" ]] || exit 0
# shellcheck source=/dev/null
source "$LIB_MODULE"

HOST_DISPLAY="${HOST_NAME:-🖥 $(hostname)}"

mkdir -p "$STATE_DIR"

command -v nvme >/dev/null 2>&1 || exit 0
command -v smartctl >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
until internet_up; do
  log SSD_WRITES "Waiting for internet..."
  sleep 5
done

sleep 10

log SSD_WRITES "SSD daily writes monitor started"

# ────────────────────────────────────────────────
# Load previous boot state (FRIENDLY NAME → value)
# ────────────────────────────────────────────────
declare -A PREV=()
declare -A CURRENT=()

if [[ -f "$STATE_FILE" ]] && jq . "$STATE_FILE" >/dev/null 2>&1; then
  while IFS="=" read -r key val; do
    [[ -n "$key" && "$key" != "timestamp" ]] || continue
    [[ "$val" =~ ^[0-9]+$ ]] || continue
    PREV["$key"]="$val"
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
  [[ "$curr" =~ ^[0-9]+$ ]] || continue

  name=$(ssd_friendly_name "$dev")
  [[ -n "$name" ]] || continue

  CURRENT["$name"]="$curr"

  prev="${PREV[$name]:-}"

  if [[ -n "$prev" ]]; then
    delta=$((curr - prev))
    (( delta >= 0 )) || delta=0
    gb=$(awk "BEGIN {printf \"%.2f\", $delta * 512000 / 1000 / 1000 / 1000}")
  else
    gb="0.00"
  fi

  report+="💽 ${name}
Writes since last boot: ${gb} GB

"

  total_gb=$(awk "BEGIN {printf \"%.2f\", $total_gb + $gb}")
done

report+="*📦 Total SSD Writes: ${total_gb} GB*"

# ────────────────────────────────────────────────
# Send Telegram
# ────────────────────────────────────────────────
log SSD_WRITES "Sending daily SSD write report (${total_gb} GB)"
tg_send "$report"

# ────────────────────────────────────────────────
# Save current state for next boot (FRIENDLY NAME keys)
# ────────────────────────────────────────────────
tmp=$(mktemp)
echo "{}" > "$tmp"

for name in "${!CURRENT[@]}"; do
  jq --arg key "$name" --argjson val "${CURRENT[$name]}" \
    '. + {($key): $val}' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
done

jq --arg ts "$(date -Is)" '. + {timestamp: $ts}' "$tmp" > "$STATE_FILE"
rm -f "$tmp"

log SSD_WRITES "SSD write state updated"
