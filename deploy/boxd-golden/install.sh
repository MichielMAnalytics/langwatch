#!/usr/bin/env bash
# One-time bootstrap: installs the golden-sync systemd timer + service.
# Idempotent — safe to re-run after script edits.
#
# Run inside the boxd VM:
#   bash /home/boxd/langwatch/deploy/boxd-golden/install.sh
#
# Forks of a VM that already has this installed don't need to re-run it —
# they inherit the systemd unit + /etc/golden-sync.conf. To track a
# different branch on a fork, edit /etc/golden-sync.conf then
# `sudo systemctl restart golden-sync.timer`.
set -euo pipefail

REPO_DIR=${REPO_DIR:-/home/boxd/langwatch}
BRANCH=${BRANCH:-main}
HERE="$REPO_DIR/deploy/boxd-golden"

# 1. Default config — preserve existing values so PR forks keep their branch.
if [ ! -f /etc/golden-sync.conf ]; then
  echo "==> writing /etc/golden-sync.conf"
  sudo tee /etc/golden-sync.conf >/dev/null <<EOF
BRANCH=$BRANCH
REPO_DIR=$REPO_DIR
EOF
else
  echo "==> /etc/golden-sync.conf already present, leaving as-is:"
  sed 's/^/    /' /etc/golden-sync.conf
fi

# 2. Install systemd units (always overwrite — they're versioned in repo).
echo "==> installing systemd units"
sudo cp "$HERE/golden-sync.service" /etc/systemd/system/golden-sync.service
sudo cp "$HERE/golden-sync.timer"   /etc/systemd/system/golden-sync.timer
sudo systemctl daemon-reload

# 3. Enable + start the timer.
echo "==> enabling golden-sync.timer"
sudo systemctl enable --now golden-sync.timer

# 4. Show status.
echo "==> timer status:"
systemctl status golden-sync.timer --no-pager --lines=0 || true
echo "==> next scheduled fire:"
systemctl list-timers golden-sync.timer --no-pager || true
