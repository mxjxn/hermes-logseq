#!/usr/bin/env bash
# hermes-logseq-stack/scripts/git-watcher.sh
# Auto-pulls from GitHub so server-side graph stays in sync with desktop edits.
# Designed for desktop-assisted workflows (Logseq desktop + git plugin).
#
# Usage: pm2 start git-watcher.sh --name logseq-git-watcher
#
# Configure:
#   GRAPH_DIR   — path to your Logseq graph (contains pages/ and journals/)
#   POLL_INTERVAL — seconds between checks (default: 120)

set -euo pipefail

GRAPH_DIR="${GRAPH_DIR:-$HOME/my-logseq-graph}"
POLL_INTERVAL="${POLL_INTERVAL:-120}"

cd "$GRAPH_DIR" || { echo "ERROR: $GRAPH_DIR not found"; exit 1; }

echo "[git-watcher] Watching $GRAPH_DIR (poll every ${POLL_INTERVAL}s)"

while true; do
  git fetch origin --quiet 2>/dev/null
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse "origin/HEAD" 2>/dev/null || git rev-parse "origin/main" 2>/dev/null || git rev-parse "origin/master" 2>/dev/null)

  if [ "$LOCAL" != "$REMOTE" ]; then
    echo "[git-watcher] $(date '+%Y-%m-%d %H:%M:%S') Pulling changes ($LOCAL → $REMOTE)"
    # Handle merge conflicts — prefer remote (desktop edits) over local
    git stash 2>/dev/null
    git pull --quiet 2>/dev/null || {
      # On conflict: take remote version (desktop user's edits win)
      CONFLICTS=$(git diff --name-only --diff-filter=U)
      for f in $CONFLICTS; do
        echo "[git-watcher] Conflict in $f — taking remote version"
        git checkout --theirs "$f" 2>/dev/null
        git add "$f"
      done
      git commit --no-edit --quiet 2>/dev/null || true
    }
    git stash pop 2>/dev/null || true
  fi

  sleep "$POLL_INTERVAL"
done
