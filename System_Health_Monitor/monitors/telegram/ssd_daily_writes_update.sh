#!/usr/bin/env bash
# SSD Write Report at BOOT (NVMe SMART based)
# Reports writes since LAST BOOT in GB
# Uses SSD MODEL NAME as identity (safe against nvme reordering)

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

sleep 75
log SSD_WRITES "SSD daily writes monitor started"

# ────────────────────────────────────────────────
# Load previous boot state (MODEL → value)
# ────────────────────────────────────────────────
declare -A PREV=()
declare -A CURRENT=()

if [[ -f "$STATE_FILE" ]] && jq . "$STATE_FILE" >/dev/null 2>&1; then
  while IFS="=" read -r model val; do
    [[ -n "$model" && "$model" != "timestamp" ]] || continue
    [[ "$val" =~ ^[0-9]+$ ]] || continue
    PREV["$model"]="$val"
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
if (( ${#PREV[@]} > 0 )); then
  log SSD_WRITES "Sending daily SSD write report (${total_gb} GB)"
  tg_send "$report"
else
  log SSD_WRITES "No previous boot data; skipping report"
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

log SSD_WRITES "SSD write state updated"
