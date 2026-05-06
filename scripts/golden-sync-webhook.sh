#!/usr/bin/env bash
# Fire-and-forget wrapper used by the webhook hook entry. Detaches the
# real sync to the background so the webhook handler can reply 200 to
# GitHub within its 10s deadline even if the deploy itself takes 60-90s.
set -euo pipefail
LOG=/var/log/golden-sync.log
nohup bash /home/boxd/langwatch/scripts/golden-sync.sh \
  >>"$LOG" 2>&1 </dev/null &
disown
echo "queued ($(date -u +%FT%TZ))"
