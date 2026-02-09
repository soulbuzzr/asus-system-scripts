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

# ================= PATHS =================
STATE_DIR="$HOME/System_Scripts"
STATE_FILE="$STATE_DIR/trim_status.json"
mkdir -p "$STATE_DIR"

HOST_DISPLAY="${HOST_NAME:-💻 $(hostname)}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# ================= WAIT FOR NETWORK =================
wait_for_network SSD_TRIM

# ================= RUN FSTRIM =================
log SSD_TRIM "starting fstrim"

TRIM_OUTPUT="$(sudo fstrim -av 2>&1)"
RC=$?

if (( RC == 0 )); then
  STATUS="success"
  ICON="✅"
else
  STATUS="failed"
  ICON="❌"
fi

log SSD_TRIM "fstrim completed status=${STATUS}"

# ================= WRITE JSON STATE =================
jq -n \
  --arg time "$TS" \
  --arg status "$STATUS" \
  --arg output "$TRIM_OUTPUT" \
  '{
    last_trim_time: $time,
    status: $status,
    output: $output
  }' > "$STATE_FILE"

# ================= TELEGRAM MESSAGE =================
MSG="*$HOST_DISPLAY*

🧹 *SSD TRIM Report*

Status: ${ICON} *${STATUS}*

\`\`\`
${TRIM_OUTPUT}
\`\`\`

🕒 *${TS}*"

tg_send_trim "$MSG"

# ================= PRESERVE ORIGINAL BEHAVIOR =================
echo "$TRIM_OUTPUT"
exit "$RC"
