#!/bin/bash
set -euo pipefail

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

STATE="$HOME/System_Scripts/trim_status.json"

command -v jq >/dev/null || exit 0
[ -f "$STATE" ] || exit 0

LAST=$(jq -r '.last_trim_time // empty' "$STATE")
[ -n "$LAST" ] || exit 0

NOW=$(date +%s)
THEN=$(date -d "$LAST" +%s 2>/dev/null || exit 0)

(( (NOW - THEN) < 604800 )) && exit 0   # < 7 days

MSG="🧹 *SSD TRIM REMINDER*

Last trim:
🕒 *$LAST*

⏰ It’s time to run:
\`sudo fstrim -av\`"

curl -s -X POST "https://api.telegram.org/bot$TG_SSD_TRIM_BOT_TOKEN/sendMessage" \
  -d chat_id="$TG_CHAT_ID" \
  -d text="$MSG" \
  -d parse_mode=Markdown \
  -d disable_web_page_preview=true >/dev/null
