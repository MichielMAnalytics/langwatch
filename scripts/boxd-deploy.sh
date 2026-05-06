#!/usr/bin/env bash
# Conditional deploy script for the langwatch-golden boxd VM.
# Invoked by .github/workflows/deploy.yml after `git fetch + checkout -B main`.
#
# Goal: the cheapest action that's still correct, picked from the diff.
#
#   source-only push          → no restart (Vite HMR picks up via volume mount)
#   deps / schema / migration → `restart init app` (~60–90s downtime)
#   compose.dev.yml / .env    → `up -d --force-recreate` (re-reads env_file)
#
# Most pushes to a busy repo are source-only — skipping the restart in that
# case eliminates the boxd "Waiting for your app on port 5560" page that
# would otherwise show on every push.
set -euo pipefail

APP_PORT=${APP_PORT:-5560}
COMPOSE="docker compose -f compose.dev.yml"

HEAD_SHA=$(git rev-parse HEAD)

# `git checkout -B main origin/main` writes two reflog entries at the same SHA
# (branch reset + checkout), so HEAD@{1} is the new commit, not the previous
# one. Walk the reflog until we find an entry that differs from HEAD.
PREV_SHA=$(git reflog HEAD --format='%H' 2>/dev/null \
  | awk -v cur="$HEAD_SHA" '$1!=cur {print $1; exit}')

if [ -z "$PREV_SHA" ]; then
  # First deploy (no reflog history before HEAD) — be safe and restart.
  echo "no prior deployed commit found in reflog — defaulting to restart"
  CHANGED=""
  ACTION="restart"
else
  CHANGED=$(git diff --name-only "$PREV_SHA" "$HEAD_SHA" 2>/dev/null || echo "")
  echo "changed files ($PREV_SHA..$HEAD_SHA):"
  echo "$CHANGED" | sed 's/^/  /'

  ACTION="none"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
      compose.dev.yml | compose.yml | langwatch/.env.example)
        ACTION="recreate"; break ;;
      package.json | langwatch/package.json | pnpm-lock.yaml | \
      langwatch/prisma/schema.prisma | \
      langwatch/prisma/migrations/* | \
      langwatch/src/server/clickhouse/migrations/* | \
      langwatch/scripts/start.sh | \
      langwatch/scripts/generate-zod-types.sh)
        # Capture but keep scanning — recreate trumps restart.
        [ "$ACTION" != "recreate" ] && ACTION="restart" ;;
    esac
  done <<< "$CHANGED"
fi

echo "deploy action: $ACTION"
case "$ACTION" in
  recreate)
    APP_PORT=$APP_PORT $COMPOSE up -d --force-recreate
    ;;
  restart)
    APP_PORT=$APP_PORT $COMPOSE restart init app
    ;;
  none)
    echo "source-only change — Vite HMR picks up via volume mount, no restart needed"
    ;;
esac

echo "deployed $(git rev-parse --short HEAD)"
