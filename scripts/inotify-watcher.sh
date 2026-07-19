#!/usr/bin/env bash
# hermes-logseq-stack/scripts/inotify-watcher.sh
# Watches pages/ and journals/ for file changes, triggers logseqd reindex.
#
# Requires: inotify-tools (inotifywait)
# Install:  apt install inotify-tools (Debian/Ubuntu) | brew install inotify-tools (macOS)
#
# Usage: pm2 start inotify-watcher.sh --name logseq-inotify
#
# Configure:
#   GRAPH_DIR    — path to your Logseq graph
#   LOGSEQD_PORT — port logseqd is running on (default: 8471)
#   REINDEX_URL  — full URL to the reindex endpoint

set -euo pipefail

GRAPH_DIR="${GRAPH_DIR:-$HOME/my-logseq-graph}"
LOGSEQD_PORT="${LOGSEQD_PORT:-8471}"
REINDEX_URL="${REINDEX_URL:-http://localhost:$LOGSEQD_PORT/reindex-file}"
WATCH_PATHS="$GRAPH_DIR/pages $GRAPH_DIR/journals"

for p in $WATCH_PATHS; do
  if [ ! -d "$p" ]; then
    echo "[inotify] WARNING: $p does not exist, skipping"
  fi
done

echo "[inotify] Watching for changes in: $WATCH_PATHS"
echo "[inotify] Reindex endpoint: $REINDEX_URL"

# Build watch paths that actually exist
EXISTING_PATHS=""
for p in $WATCH_PATHS; do
  [ -d "$p" ] && EXISTING_PATHS="$EXISTING_PATHS $p"
done

if [ -z "$EXISTING_PATHS" ]; then
  echo "[inotify] ERROR: No valid watch paths found"
  exit 1
fi

inotifywait -m -r -e create -e delete -e modify -e moved_to $EXISTING_PATHS 2>/dev/null | while read -r dir event file; do
  # Skip hidden files and lock files
  case "$file" in
    .DS_Store|*.swp|*.swo|*.tmp|.git/*) continue ;;
  esac

  # Only process .md files
  [[ "$file" == *.md ]] || continue

  # Strip graph dir prefix to get relative path
  REL="${dir#$GRAPH_DIR/}"
  FULL_FILE="${REL:+$REL/}$file"

  echo "[inotify] $(date '+%H:%M:%S') $event: $FULL_FILE → reindexing"

  # Send reindex request (EDN format — logseqd expects {:file "basename.md"})
  # We send the basename only; logseqd handles path resolution
  curl -s -X POST "$REINDEX_URL" \
    -H "Content-Type: application/edn" \
    -d "{:file \"$file\"}" 2>/dev/null || {
    # Fallback: reindex entire graph if single-file reindex fails
    curl -s -X POST "http://localhost:$LOGSEQD_PORT/reindex" 2>/dev/null || true
  }
done
