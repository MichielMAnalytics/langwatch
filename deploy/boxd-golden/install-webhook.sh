#!/usr/bin/env bash
# One-time bootstrap: switches the VM from polling-based sync to a
# GitHub-webhook listener. Idempotent — safe to re-run after edits.
#
# Run inside the boxd VM:
#   WEBHOOK_SECRET=<shared> bash deploy/boxd-golden/install-webhook.sh
#
# WEBHOOK_SECRET is the value you'll also set in GitHub's repo webhook
# config (Settings → Webhooks → Secret). Must match byte-for-byte.
# If WEBHOOK_SECRET is unset, generates a fresh one and prints it once.
set -euo pipefail

REPO_DIR=${REPO_DIR:-/home/boxd/langwatch}
HERE="$REPO_DIR/deploy/boxd-golden"

# 1. Stop the polling timer if it's running — webhook supersedes it.
if systemctl is-enabled --quiet golden-sync.timer 2>/dev/null; then
  echo "==> disabling polling timer (webhook supersedes)"
  sudo systemctl disable --now golden-sync.timer
fi

# 2. Install the `webhook` binary (Go, ~5MB, in Ubuntu main).
if ! command -v webhook >/dev/null 2>&1; then
  echo "==> apt installing webhook"
  sudo apt-get update -qq
  sudo apt-get install -y -qq webhook
fi

# 3. Pick up or generate the shared secret.
if [ -z "${WEBHOOK_SECRET:-}" ]; then
  if [ -f /etc/golden-webhook-secret ]; then
    WEBHOOK_SECRET=$(sudo cat /etc/golden-webhook-secret)
    echo "==> reusing existing /etc/golden-webhook-secret"
  else
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    echo "==> generated new webhook secret (will print once below)"
  fi
fi
echo "$WEBHOOK_SECRET" | sudo tee /etc/golden-webhook-secret >/dev/null
sudo chmod 600 /etc/golden-webhook-secret

# 4. Render the webhook config with the secret substituted in.
echo "==> writing /etc/golden-webhook.conf.json"
sudo sed "s|@WEBHOOK_SECRET@|$WEBHOOK_SECRET|" \
  "$HERE/webhook.conf.json.template" \
  | sudo tee /etc/golden-webhook.conf.json >/dev/null
sudo chmod 600 /etc/golden-webhook.conf.json

# 5. Log file for the async sync's stdout/stderr.
sudo touch /var/log/golden-sync.log
sudo chown boxd:boxd /var/log/golden-sync.log

# 6. Install + start the systemd unit.
echo "==> installing systemd unit"
sudo cp "$HERE/golden-webhook.service" /etc/systemd/system/golden-webhook.service
sudo systemctl daemon-reload
sudo systemctl enable --now golden-webhook.service

# 7. Show status + the secret (only on first install / for confirmation).
echo "==> webhook listener status:"
systemctl status golden-webhook.service --no-pager --lines=0 || true
echo ""
echo "==> webhook secret (set this in GitHub → Settings → Webhooks → Secret):"
echo "    $WEBHOOK_SECRET"
echo ""
echo "==> next steps from your laptop:"
echo "    boxd proxy new --vm langwatch-golden --port 9000 hooks"
echo "    # then point the GitHub webhook to:"
echo "    #   https://hooks.langwatch-golden.boxd.sh/hooks/deploy"
