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

: "${TG_SSD_TRIM_BOT_TOKEN:?Missing TG_SSD_TRIM_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

# ================= LOG FILE =================
LOG_DIR="/var/log/system_health"
LOG_FILE="$LOG_DIR/health.log"
mkdir -p "$LOG_DIR"

# ================= BASICS =================
HOST='💻  ASUS Linux Workstation'
TS=$(date '+%Y-%m-%d %H:%M:%S')

STATE_DIR="$HOME/System_Scripts"
JSON_FILE="$STATE_DIR/trim_status.json"
mkdir -p "$STATE_DIR"

command -v jq >/dev/null 2>&1 || exit 1
command -v fstrim >/dev/null 2>&1 || exit 1

# ================= RUN FSTRIM =================
TRIM_OUTPUT="$(sudo fstrim -av 2>&1)"
RC=$?

if [[ $RC -eq 0 ]]; then
  STATUS="success"
  ICON="✅"
else
  STATUS="failed"
  ICON="❌"
fi

# ================= WRITE JSON STATE =================
jq -n \
  --arg time "$TS" \
  --arg status "$STATUS" \
  --arg output "$TRIM_OUTPUT" \
  '{
    last_trim_time: $time,
    status: $status,
    output: $output
  }' > "$JSON_FILE"

# ================= TELEGRAM MESSAGE =================
MSG="*$HOST*

🧹 *SSD TRIM Report*

Status: ${ICON} *${STATUS}*

\`\`\`
${TRIM_OUTPUT}
\`\`\`

🕒 *${TS}*"

# ================= LOG =================
echo "$(echo "$MSG" | sed 's/\*//g')" >> "$LOG_FILE"

# ================= TELEGRAM =================
curl -s -X POST "https://api.telegram.org/bot$TG_SSD_TRIM_BOT_TOKEN/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  -d text="$MSG" \
  -d parse_mode=Markdown \
  -d disable_web_page_preview=true >/dev/null

# ================= PRESERVE FSTRIM BEHAVIOR =================
echo "$TRIM_OUTPUT"
exit $RC
