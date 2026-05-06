#!/usr/bin/env bash
# Polled by systemd timer (golden-sync.timer). Fetches the configured
# branch from origin and runs scripts/boxd-deploy.sh if it has moved.
#
# Configuration lives at /etc/golden-sync.conf so PR-fork VMs can rewrite
# the tracked branch without touching the repo:
#
#   BRANCH=main                       # branch to track
#   REPO_DIR=/home/boxd/langwatch     # repo working tree
#
# Defaults are golden-VM-appropriate. Forks of the golden inherit the
# config file and the timer; only the branch line needs to change.
set -euo pipefail

CONF=/etc/golden-sync.conf
[ -f "$CONF" ] && . "$CONF"
BRANCH=${BRANCH:-main}
REPO_DIR=${REPO_DIR:-/home/boxd/langwatch}

cd "$REPO_DIR"

git fetch --quiet origin "$BRANCH"
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi

# Mark deploy in progress so concurrent /boxd-preview triggers can hold
# off until we settle. Lock cleared on any exit; "last completed" is
# only written after boxd-deploy.sh finishes successfully.
LOCK=/tmp/golden-sync.lock
LAST=/tmp/golden-sync.last
touch "$LOCK"
trap 'rm -f "$LOCK"' EXIT

echo "$(date -Is) sync: $LOCAL -> $REMOTE on $BRANCH"
git checkout -B "$BRANCH" "origin/$BRANCH"
bash scripts/boxd-deploy.sh
date +%s > "$LAST"
