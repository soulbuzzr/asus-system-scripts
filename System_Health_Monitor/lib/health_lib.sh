#!/bin/bash
set -u
set -o pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

BASE_DIR="$HOME/System_Scripts/System_Health_Monitor"
ENV_FILE="$BASE_DIR/env/system_health_bot.env"
CONF_FILE="$BASE_DIR/conf/system_limits.conf"

# ================= LOAD ENV =================
if [ ! -r "$ENV_FILE" ]; then
  echo "ERROR: Missing env file: $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

: "${TG_BOT_TOKEN:?Missing TG_BOT_TOKEN}"
: "${TG_HOURLY_BOT_TOKEN:?Missing TG_HOURLY_BOT_TOKEN}"
: "${TG_SSD_TRIM_BOT_TOKEN:?Missing TG_SSD_TRIM_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

# ================= LOAD CONFIG =================
if [ ! -r "$CONF_FILE" ]; then
  echo "ERROR: Missing config file: $CONF_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONF_FILE"

# ================= LOGGING =================
LOG_DIR="/var/log/system_health"
LOG_FILE="$LOG_DIR/health.log"

mkdir -p "$LOG_DIR"

log() {
  # Usage: log COMPONENT MESSAGE
  echo "$(date '+%F %T') [$1] $2" >> "$LOG_FILE"
}

# ================= TELEGRAM CORE =================
tg_send_common() {
  local token="$1"
  local message="$2"
  [ -n "$token" ] || return 1

  curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$message" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null
}

tg_send()        { tg_send_common "$TG_BOT_TOKEN" "$1"; }
tg_send_hourly() { tg_send_common "$TG_HOURLY_BOT_TOKEN" "$1"; }
tg_send_trim()   { tg_send_common "$TG_SSD_TRIM_BOT_TOKEN" "$1"; }

# ================= NETWORK =================
internet_up() {
  ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

wait_for_network() {
  local tag="${1:-NET}"
  until internet_up; do
    log "$tag" "Waiting for internet..."
    sleep 5
  done
}

startup_notify() {
  local tag="$1"
  local message="$2"
  local sender="${3:-tg_send}"   # default bot
  
  if ! type "$sender" >/dev/null 2>&1; then
    sender="tg_send"
  fi

  log "$tag" "monitor started"
  "$sender" "$message"
}

# ================= NVME DISCOVERY =================
get_nvme_devices() {
  smartctl --scan 2>/dev/null | awk '{print $1}' 
}

# ================= SSD MODEL NAME =================
ssd_model_name() {
  local dev="$1"

  nvme id-ctrl "$dev" 2>/dev/null \
    | awk -F: '/^mn/ {gsub(/^[ \t]+/,"",$2); print $2; exit}'
}

# ================= SSD FRIENDLY NAME =================
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

# ================= SSD HEALTH =================
ssd_health_percent() {
  nvme smart-log "$1" 2>/dev/null \
    | awk -F'[:%]' '/^percentage_used/ {print 100-$2}'
}

# ================= SSD SPARE USED =================
ssd_spare_used() {
  nvme smart-log "$1" 2>/dev/null \
    | awk -F'[:%]' '/^available_spare/&&!/_threshold/ {print 100-$2}'
}

# ================= SSD TEMP =================
ssd_temperature() {
  nvme smart-log "$1" 2>/dev/null \
    | awk -F'[(:]' '/^temperature/ {print $2+0}'
}

# ================= SSD DATA UNITS WRITTEN =================
get_written_units() {
  # Returns NVMe Data Units Written (raw units, numeric)
  smartctl -a "$1" 2>/dev/null \
    | awk -F: '/Data Units Written/ {print $2}' \
    | awk '{print $1}' \
    | tr -d ','
}

# NVMe data units → GB
# NVMe spec: 1 unit = 512 KB
nvme_units_to_gb() {
  local units="$1"
  awk "BEGIN {printf \"%.2f\", $units * 512000 / 1000 / 1000 / 1000}"
}


load_json_state() {
  local file="$1"
  local _arr="$2"

  [[ -f "$file" ]] || return 0
  jq . "$file" >/dev/null 2>&1 || return 0

  while IFS="=" read -r k v; do
    [[ "$k" == "timestamp" ]] && continue
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    eval "$_arr[\"\$k\"]=\"\$v\""
  done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$file")
}

save_json_state() {
  local file="$1"
  local _arr="$2"

  local tmp
  tmp=$(mktemp)
  echo "{}" > "$tmp"

  eval "for k in \"\${!$_arr[@]}\"; do
    jq --arg key \"\$k\" --argjson val \"\${$_arr[\$k]}\" \
      '. + {(\$key): \$val}' \"$tmp\" > \"\$tmp.new\" && mv \"\$tmp.new\" \"$tmp\"
  done"

  jq --arg ts "$(date -Is)" '. + {timestamp: $ts}' "$tmp" > "$file"
  rm -f "$tmp"
}

# ================= GPU TEMP =================
read_gpu_temp() {
  nvidia-smi --query-gpu=temperature.gpu \
             --format=csv,noheader,nounits 2>/dev/null
}

# ================= BATTERY UTILITIES =================
battery_path() {
  ls -d /sys/class/power_supply/BAT* 2>/dev/null 
}

battery_present() {
  [ -n "$(battery_path)" ]
}

battery_health_percent() {
  local full design

  full=$(cat "$(battery_path)/charge_full" 2>/dev/null) || return
  design=$(cat "$(battery_path)/charge_full_design" 2>/dev/null) || return

  [ -n "$full" ] && [ -n "$design" ] && [ "$design" -gt 0 ] || return

  echo $(( full * 100 / design ))
}

battery_charge_percent() {
  cat "$(battery_path)/capacity" 2>/dev/null
}

# ================= AVERAGING =================
avg_over_seconds() {
  local seconds="$1" reader="$2"
  local sum=0 count=0

  for _ in $(seq 1 "$seconds"); do
    val="$($reader 2>/dev/null || true)"
    [[ "$val" =~ ^[0-9]+$ ]] && { sum=$((sum + val)); count=$((count + 1)); }
    sleep 1
  done

  (( count == 0 )) && return 1
  awk -v s="$sum" -v c="$count" 'BEGIN{printf "%.2f", s/c}'
}

# ================= FLOAT HELPERS =================
float_gt() { awk "BEGIN{exit !($1 >  $2)}"; }
float_lt() { awk "BEGIN{exit !($1 <  $2)}"; }

# ================= MEDIAN =================
median() {
  local arr=("$@")
  local n=${#arr[@]}

  IFS=$'\n' sorted=($(sort -n <<<"${arr[*]}"))
  unset IFS

  if (( n % 2 == 1 )); then
    echo "${sorted[$((n/2))]}"
  else
    awk "BEGIN{printf \"%.1f\", (${sorted[$((n/2-1))]} + ${sorted[$((n/2))]}) / 2}"
  fi
}

# ================= Mean Average Deviation =================
mad() {
  local arr=("$@")
  local med
  med=$(median "${arr[@]}")

  local devs=()
  for v in "${arr[@]}"; do
    devs+=("$(awk "BEGIN{print ($v > $med) ? $v-$med : $med-$v}")")
  done

  median "${devs[@]}"
}