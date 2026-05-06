#!/usr/bin/env bash
# Handler for the `/preview` slash-command on a PR. Invoked by webhook(8)
# after the cheap layer-A gate (HMAC, comment body, author_association,
# is-PR) has passed. This script is the precise gate (layer B): it asks
# GitHub for the commenter's effective repo permission and bounces if
# they don't have write+.
#
# Args (from pass-arguments-to-command in webhook.conf.json):
#   $1  comment.user.login
#   $2  issue.number  (PR number)
#   $3  repository.full_name  (e.g. MichielMAnalytics/langwatch)
#
# Detached background pattern: this script returns immediately so the
# webhook(8) handler can reply 200 to GitHub within its 10s deadline.
set -euo pipefail

LOG=/var/log/golden-preview.log

if [ -t 1 ] || [ "${PREVIEW_FOREGROUND:-0}" = "1" ]; then
  : # already in fg (manual run)
else
  # Re-exec self in the background so the webhook returns fast.
  PREVIEW_FOREGROUND=1 nohup "$0" "$@" >>"$LOG" 2>&1 </dev/null &
  disown
  echo "queued"
  exit 0
fi

COMMENTER=${1:?missing arg: commenter}
PR_NUMBER=${2:?missing arg: pr_number}
REPO=${3:?missing arg: repo}

echo
echo "$(date -u +%FT%TZ) /preview from @$COMMENTER on $REPO#$PR_NUMBER"

# Layer B gate: precise per-repo permission via GitHub API.
PERM=$(gh api "repos/$REPO/collaborators/$COMMENTER/permission" --jq '.permission' 2>&1 \
  || echo "lookup_failed")
echo "  permission: $PERM"

case "$PERM" in
  admin|maintain|write) ;;
  *)
    gh pr comment "$PR_NUMBER" --repo "$REPO" --body \
      "@$COMMENTER /preview requires write access to this repo. Your effective permission is \`$PERM\`."
    echo "  bounced (insufficient permission)"
    exit 0
    ;;
esac

# Placeholder until the fork-and-checkout flow is wired up.
gh pr comment "$PR_NUMBER" --repo "$REPO" --body \
  "[gating-ok] @$COMMENTER triggered /preview (perm: \`$PERM\`). Fork-and-deploy not wired up yet — coming next."
echo "  gating passed; placeholder comment posted"
