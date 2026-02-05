#!/usr/bin/env bash

set -euo pipefail

JSON_FILE="/home/sughosha/System_Scripts/trim_status.json"

# Run fstrim and capture output
TRIM_OUTPUT="$(sudo fstrim -av 2>&1)"
RC=$?

if [[ $RC -eq 0 ]]; then
  STATUS="success"
else
  STATUS="failed"
fi

# Write JSON safely using jq
jq -n \
  --arg time "$(date -Is)" \
  --arg status "$STATUS" \
  --arg output "$TRIM_OUTPUT" \
  '{
    last_trim_time: $time,
    status: $status,
    output: $output
  }' > "$JSON_FILE"

# Preserve normal fstrim behavior
echo "$TRIM_OUTPUT"
exit $RC
