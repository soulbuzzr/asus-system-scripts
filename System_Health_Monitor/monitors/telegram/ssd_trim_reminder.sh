#!/bin/bash
set -euo pipefail

# ================= RESOLVE HOME DIRECTORY for root user =================
if [[ "$HOME" == "/root" ]]; then
  HOME="/home/sughosha"
fi

# ================= LOAD SHARED LIB =================
source "$HOME/System_Scripts/System_Health_Monitor/lib/health_lib.sh"

# ================= VALIDATION =================
: "${TG_SSD_TRIM_BOT_TOKEN:?Missing TG_SSD_TRIM_BOT_TOKEN}"
: "${TG_CHAT_ID:?Missing TG_CHAT_ID}"

STATE_FILE="$HOME/System_Scripts/trim_status.json"
[ -f "$STATE_FILE" ] || exit 0

# ================= READ LAST TRIM =================
LAST_TRIM=$(jq -r '.last_trim_time // empty' "$STATE_FILE")
[ -n "$LAST_TRIM" ] || exit 0

NOW=$(date +%s)
THEN=$(date -d "$LAST_TRIM" +%s 2>/dev/null || exit 0)

# ================= THRESHOLD =================
# 7 days = 604800 seconds
(( (NOW - THEN) < 604800 )) && exit 0

# ================= SEND REMINDER =================
MSG="🧹 *SSD TRIM REMINDER*

Last trim:
🕒 *${LAST_TRIM}*

⏰ It’s time to run:
\`sudo fstrim -av\`"

log SSD_TRIM "sending trim reminder (last=${LAST_TRIM})"
tg_send_trim "$MSG"
