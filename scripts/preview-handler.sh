#!/usr/bin/env bash
# Handler for the `/boxd-preview` slash-command on a PR. Invoked by
# webhook(8) after the cheap layer-A gate (HMAC, comment body,
# author_association ∈ {OWNER, MEMBER, COLLABORATOR}, is-PR) has passed.
#
# Layer-B (precise auth) and the actual fork-and-checkout work happen
# here, in the background, so the webhook returns 200 fast.
#
# Args (from pass-arguments-to-command):
#   $1  comment.user.login
#   $2  issue.number  (PR number)
#   $3  repository.full_name  (owner/repo)
#   $4  comment.id    (the triggering comment, for the eyes reaction)
set -euo pipefail

LOG=/var/log/golden-preview.log

if [ -t 1 ] || [ "${PREVIEW_FOREGROUND:-0}" = "1" ]; then
  : # already in fg
else
  PREVIEW_FOREGROUND=1 nohup "$0" "$@" >>"$LOG" 2>&1 </dev/null &
  disown
  echo "queued"
  exit 0
fi

COMMENTER=${1:?missing arg: commenter}
PR_NUMBER=${2:?missing arg: pr_number}
REPO=${3:?missing arg: repo}
COMMENT_ID=${4:?missing arg: comment_id}

echo
echo "$(date -u +%FT%TZ) /boxd-preview @$COMMENTER on $REPO#$PR_NUMBER (comment $COMMENT_ID)"

# Eyes reaction — Layer-A already filtered randoms.
gh api -X POST "repos/$REPO/issues/comments/$COMMENT_ID/reactions" \
  -f content=eyes >/dev/null 2>&1 || echo "  (eyes reaction failed; continuing)"

# Layer-B: precise per-repo permission.
PERM=$(gh api "repos/$REPO/collaborators/$COMMENTER/permission" --jq '.permission' 2>&1 \
  || echo "lookup_failed")
echo "  permission: $PERM"

case "$PERM" in
  admin|maintain|write) ;;
  *)
    gh pr comment "$PR_NUMBER" --repo "$REPO" --body \
      "@$COMMENTER /boxd-preview requires write access. Your effective permission is \`$PERM\`."
    echo "  bounced (insufficient permission)"
    exit 0
    ;;
esac

# Don't fork a golden that's mid-deploy or just-deployed — the fork
# would inherit the in-progress state.
LOCK=/tmp/golden-sync.lock
LAST=/tmp/golden-sync.last
COOLDOWN_S=30
NOW=$(date +%s)
COOLDOWN_REASON=""

if [ -f "$LOCK" ]; then
  AGE=$((NOW - $(stat -c %Y "$LOCK" 2>/dev/null || echo "$NOW")))
  if [ "$AGE" -lt 600 ]; then
    COOLDOWN_REASON="a golden deploy is in progress (started ${AGE}s ago)"
  fi
fi
if [ -z "$COOLDOWN_REASON" ] && [ -f "$LAST" ]; then
  AGE=$((NOW - $(cat "$LAST" 2>/dev/null || echo 0)))
  if [ "$AGE" -lt "$COOLDOWN_S" ]; then
    COOLDOWN_REASON="golden was updated ${AGE}s ago, give it ~$((COOLDOWN_S-AGE))s to settle"
  fi
fi

if [ -n "$COOLDOWN_REASON" ]; then
  gh pr comment "$PR_NUMBER" --repo "$REPO" --body \
    "@$COMMENTER ⏸ $COOLDOWN_REASON. Try \`/boxd-preview\` again in a moment."
  echo "  cooldown: $COOLDOWN_REASON — bounced"
  exit 0
fi

# Resolve PR branch + target VM name.
PR_BRANCH=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .head.ref)
VM_NAME="langwatch-pr-$PR_NUMBER"
URL="https://$VM_NAME.boxd.sh"
echo "  branch: $PR_BRANCH"
echo "  vm: $VM_NAME"
echo "  url: $URL"

# Post the booting comment + capture its id so we can edit it later.
BOOT_BODY="⏳ booting boxd preview for \`$PR_BRANCH\` → $URL"
BOOT_COMMENT_ID=$(gh api -X POST "/repos/$REPO/issues/$PR_NUMBER/comments" \
  -f body="$BOOT_BODY" --jq .id)
echo "  boot comment id: $BOOT_COMMENT_ID"

# Fork golden if the VM doesn't exist yet, otherwise reuse.
if boxd list --json 2>/dev/null | jq -e ".[] | select(.name==\"$VM_NAME\")" >/dev/null; then
  echo "  VM $VM_NAME already exists — reusing"
else
  echo "  forking golden → $VM_NAME"
  boxd fork --name "$VM_NAME" --json >/dev/null
fi

# Forks inherit the default proxy (langwatch-pr-N.boxd.sh → :8000 by
# default). Force it to 5560 to match the langwatch app port.
boxd proxy set-port --vm "$VM_NAME" --port 5560 2>&1 \
  | sed 's/^/  proxy: /' || true

# Switch the fork's working tree to the PR branch. We use `git reset
# --hard` here (rather than golden-sync.sh's safer `checkout -B`) because
# the fork inherits any in-flight working-tree mods from the golden, and
# for a disposable preview fork it's safe to clobber them.
echo "BRANCH=$PR_BRANCH
REPO_DIR=/home/boxd/langwatch" | boxd cp - "$VM_NAME":/tmp/golden-sync.conf
boxd exec "$VM_NAME" -- bash -c "
set -e
sudo mv /tmp/golden-sync.conf /etc/golden-sync.conf
cd /home/boxd/langwatch
git fetch --quiet origin '$PR_BRANCH'
git reset --hard 'origin/$PR_BRANCH'
bash scripts/boxd-deploy.sh
" 2>&1 | sed 's/^/  fork-sync: /'

# Wait for the fork to start serving on its public URL. ~5min upper bound.
echo "  waiting for $URL …"
READY="no"
for i in $(seq 1 60); do
  CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "$URL/" 2>/dev/null || echo "000")
  if [[ "$CODE" =~ ^[23] ]]; then READY="yes"; break; fi
  sleep 5
done
echo "  ready=$READY (last HTTP $CODE) after $((i*5))s"

# Update the booting comment with the result.
if [ "$READY" = "yes" ]; then
  gh api -X PATCH "/repos/$REPO/issues/comments/$BOOT_COMMENT_ID" \
    -f body="✅ preview ready for \`$PR_BRANCH\`: $URL" >/dev/null
else
  gh api -X PATCH "/repos/$REPO/issues/comments/$BOOT_COMMENT_ID" \
    -f body="⚠️ preview boot timed out at $URL (last HTTP $CODE). Debug: \`boxd exec $VM_NAME -- docker ps\`." >/dev/null
fi
echo "  done"
