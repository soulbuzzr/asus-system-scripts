#!/usr/bin/env bash
set -u
set -o pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

STATE_DIR="$HOME/System_Scripts"
STATE_FILE="$STATE_DIR/last_boot.json"
mkdir -p "$STATE_DIR"

command -v nvme >/dev/null 2>&1 || exit 0
command -v smartctl >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# ================= WAIT FOR NETWORK =================
wait_for_network SSD_WRITES
sleep 10

log SSD_WRITES "SSD write report started"
# ================= LOAD PREVIOUS STATE =================
declare -A PREV=()
declare -A CURRENT=()

load_json_state "$STATE_FILE" PREV

# ================= BUILD REPORT =================
report="*📊 SSD Write Report (since last boot)*
*${HOST_NAME:-🖥 $(hostname)}*
*🕒 $(date)*

"

total_gb=0

for DEV in $(get_nvme_devices); do
  curr=$(get_written_units "$DEV")
  [[ "$curr" =~ ^[0-9]+$ ]] || continue

  name=$(ssd_friendly_name "$DEV")
  [[ -n "$name" ]] || continue

  CURRENT["$name"]="$curr"

  prev="${PREV[$name]:-0}"
  delta=$(( curr - prev ))
  (( delta < 0 )) && delta=0

  gb=$(nvme_units_to_gb "$delta")
  total_gb=$(awk "BEGIN {printf \"%.2f\", $total_gb + $gb}")

  report+="💽 ${name}
Writes since last boot: ${gb} GB

"
done

report+="*📦 Total SSD Writes: ${total_gb} GB*"

# ================= SEND =================
log SSD_WRITES "Sending SSD write report (${total_gb} GB)"
tg_send "$report"

# ================= SAVE STATE =================
save_json_state "$STATE_FILE" CURRENT

log SSD_WRITES "SSD write state updated"
