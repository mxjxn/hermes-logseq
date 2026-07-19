#!/usr/bin/env bash
# hermes-logseq-stack/setup.sh
# Installer for the Hermes + Logseq knowledge graph stack.
# Sets up logseqd, inotify watcher, viewer, and Hermes skills.
#
# Supported: Linux (Debian/Ubuntu), macOS
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}→${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }

# Detect OS
detect_os() {
  case "$(uname -s)" in
    Linux*)  OS="linux"; PKG_MANAGER=$(command -v apt &>/dev/null && echo "apt" || command -v dnf &>/dev/null && echo "dnf" || echo "unknown") ;;
    Darwin*) OS="macos"; PKG_MANAGER="brew" ;;
    *)       fail "Unsupported OS: $(uname -s)" ;;
  esac
}

# Check dependencies
check_deps() {
  MISSING=()
  command -v git &>/dev/null || MISSING+=("git")
  command -v curl &>/dev/null || MISSING+=("curl")
  command -v babashka &>/dev/null || MISSING+=("babashka")
  command -v inotifywait &>/dev/null || MISSING+=("inotify-tools")

  if [ ${#MISSING[@]} -gt 0 ]; then
    warn "Missing: ${MISSING[*]}"
    if [ "$OS" = "linux" ] && [ "$PKG_MANAGER" = "apt" ]; then
      info "Install with: sudo apt install ${MISSING[*]}"
      info "Babashka: curl -s https://babashka.org/install | bash"
    elif [ "$OS" = "macos" ]; then
      info "Install with: brew install ${MISSING[*]}"
      info "Babashka: brew install borkdude/brew/babashka"
    fi
    echo ""
    read -rp "Install missing deps now? (y/n) [y]: " INSTALL
    INSTALL="${INSTALL:-y}"
    if [ "$INSTALL" = "y" ]; then
      if [ "$OS" = "macos" ]; then
        brew install "${MISSING[@]}" || fail "Failed to install deps"
      elif [ "$PKG_MANAGER" = "apt" ]; then
        sudo apt update && sudo apt install -y "${MISSING[@]}" || fail "Failed to install deps"
      fi
    else
      fail "Cannot continue without required dependencies"
    fi
  fi
  ok "All dependencies available"
}

# Check for PM2 (process manager)
check_pm2() {
  if ! command -v pm2 &>/dev/null; then
    warn "PM2 not found (recommended for process management)"
    read -rp "Install PM2? (y/n) [y]: " INSTALL_PM2
    INSTALL_PM2="${INSTALL_PM2:-y}"
    if [ "$INSTALL_PM2" = "y" ]; then
      npm install -g pm2 || warn "Could not install PM2 — you'll need to manage processes manually"
    fi
  else
    ok "PM2 found"
  fi
}

# Prompt with default
prompt() {
  local msg="$1" default="$2"
  read -rp "$msg [$default]: " VAL
  echo "${VAL:-$default}"
}

# Interactive setup
interactive_setup() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════${NC}"
  echo -e "${CYAN}  Hermes Logseq Stack — Setup${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════${NC}"
  echo ""

  GRAPH_DIR=$(prompt "Path to your Logseq graph" "$HOME/my-logseq-graph")
  LOGSEQD_PORT=$(prompt "logseqd port" "8471")
  MODE=$(prompt "Mode: desktop or headless" "headless")
  INSTALL_VIEWER=$(prompt "Install the web viewer?" "yes")
  HERMES_SKILLS_DIR=$(prompt "Hermes skills directory" "$HOME/.hermes/skills")

  # Validate graph directory
  if [ ! -d "$GRAPH_DIR" ]; then
    warn "Graph directory does not exist: $GRAPH_DIR"
    read -rp "Create it? (y/n) [y]: " CREATE_GRAPH
    CREATE_GRAPH="${CREATE_GRAPH:-y}"
    if [ "$CREATE_GRAPH" = "y" ]; then
      mkdir -p "$GRAPH_DIR/pages" "$GRAPH_DIR/journals"
      ok "Created graph structure at $GRAPH_DIR"
    else
      fail "Need a graph directory to continue"
    fi
  fi

  # Ensure pages/ and journals/ exist
  mkdir -p "$GRAPH_DIR/pages" "$GRAPH_DIR/journals"

  echo ""
  info "Configuration:"
  echo "  Graph:        $GRAPH_DIR"
  echo "  logseqd port: $LOGSEQD_PORT"
  echo "  Mode:         $MODE"
  echo "  Viewer:       $INSTALL_VIEWER"
  echo "  Skills dir:   $HERMES_SKILLS_DIR"
  echo ""
  read -rp "Looks good? (y/n) [y]: " CONFIRM
  CONFIRM="${CONFIRM:-y}"
  [ "$CONFIRM" != "y" ] && fail "Aborted"
}

# Build logseqd
setup_logseqd() {
  cd "$SCRIPT_DIR/logseqd"

  info "Starting logseqd (port $LOGSEQD_PORT)..."
  export GRAPH_DIR
  export LOGSEQD_PORT

  if command -v pm2 &>/dev/null; then
    pm2 delete logseqd 2>/dev/null || true
    pm2 start "bb run src/api.clj" \
      --name logseqd \
      --cwd "$SCRIPT_DIR/logseqd" \
      --env GRAPH_DIR="$GRAPH_DIR" \
      --env LOGSEQD_PORT="$LOGSEQD_PORT"
    pm2 save 2>/dev/null || true
    ok "logseqd registered as PM2 process (port $LOGSEQD_PORT)"
  else
    warn "No PM2 — starting logseqd in foreground"
    info "Run: cd logseqd && GRAPH_DIR=$GRAPH_DIR LOGSEQD_PORT=$LOGSEQD_PORT bb run src/api.clj"
    return
  fi

  # Wait for logseqd to start
  sleep 2
  if curl -s "http://localhost:$LOGSEQD_PORT/pages" >/dev/null 2>&1; then
    ok "logseqd is responding"
  else
    warn "logseqd may not be ready yet — check with: curl http://localhost:$LOGSEQD_PORT/pages"
  fi
}

# Set up inotify watcher
setup_inotify() {
  info "Setting up inotify watcher..."

  if command -v pm2 &>/dev/null; then
    pm2 delete logseq-inotify 2>/dev/null || true
    pm2 start "$SCRIPT_DIR/scripts/inotify-watcher.sh" \
      --name logseq-inotify \
      --env GRAPH_DIR="$GRAPH_DIR" \
      --env LOGSEQD_PORT="$LOGSEQD_PORT"
    pm2 save 2>/dev/null || true
    ok "inotify watcher registered as PM2 process"
  else
    warn "No PM2 — run manually: GRAPH_DIR=$GRAPH_DIR LOGSEQD_PORT=$LOGSEQD_PORT scripts/inotify-watcher.sh"
  fi
}

# Set up git watcher (desktop mode only)
setup_git_watcher() {
  info "Setting up git watcher..."

  if ! git -C "$GRAPH_DIR" remote get-url origin &>/dev/null; then
    warn "No git remote configured for $GRAPH_DIR — skipping git watcher"
    warn "Set up a GitHub remote first, then re-run setup"
    return
  fi

  if command -v pm2 &>/dev/null; then
    pm2 delete logseq-git-watcher 2>/dev/null || true
    pm2 start "$SCRIPT_DIR/scripts/git-watcher.sh" \
      --name logseq-git-watcher \
      --env GRAPH_DIR="$GRAPH_DIR"
    pm2 save 2>/dev/null || true
    ok "git watcher registered as PM2 process"
  else
    warn "No PM2 — run manually: GRAPH_DIR=$GRAPH_DIR scripts/git-watcher.sh"
  fi
}

# Install viewer
setup_viewer() {
  info "Setting up viewer..."

  VIEWER_DIR=$(prompt "Where to install the viewer?" "/var/www/notes-viewer")

  if [ -d "$VIEWER_DIR" ]; then
    warn "Viewer directory exists: $VIEWER_DIR"
    read -rp "Overwrite? (y/n) [n]: " OVERWRITE
    [ "${OVERWRITE:-n}" != "y" ] && { warn "Skipping viewer install"; return; }
  fi

  mkdir -p "$VIEWER_DIR"
  cp -r "$SCRIPT_DIR/viewer/"* "$VIEWER_DIR/"
  ok "Viewer files copied to $VIEWER_DIR"

  echo ""
  info "Viewer setup notes:"
  echo "  1. Configure your web server to proxy /api → http://localhost:$LOGSEQD_PORT"
  echo "     Caddy example:"
  echo "       notes.example.com {"
  echo "         root * $VIEWER_DIR"
  echo "         file_server"
  echo "         reverse_proxy /api/* localhost:$LOGSEQD_PORT"
  echo "       }"
  echo "     Nginx example:"
  echo "       location /api/ { proxy_pass http://localhost:$LOGSEQD_PORT; }"
  echo "       location / { root $VIEWER_DIR; try_files \$uri \$uri/ /index.html; }"
  echo ""
  echo "  2. Update app.js API endpoint if not using /api proxy"
  echo ""
}

# Install Hermes skills
setup_skills() {
  info "Installing Hermes skills..."

  PARENT_DIR="$HERMES_SKILLS_DIR/hermes-logseq"
  mkdir -p "$PARENT_DIR/references" "$PARENT_DIR/scripts"

  # Copy parent skill
  cp "$SCRIPT_DIR/skills/hermes-logseq/SKILL.md" "$PARENT_DIR/SKILL.md" 2>/dev/null || warn "Parent skill SKILL.md not found"

  # Copy sub-skills
  for SKILL in hermes-logseq-viewer hermes-logseq-cron; do
    SKILL_DIR="$HERMES_SKILLS_DIR/$SKILL"
    mkdir -p "$SKILL_DIR"
    cp "$SCRIPT_DIR/skills/$SKILL/SKILL.md" "$SKILL_DIR/SKILL.md" 2>/dev/null || warn "$SKILL SKILL.md not found"
  done

  # Copy publish script
  cp "$SCRIPT_DIR/scripts/logseq-publish.py" "$PARENT_DIR/scripts/" 2>/dev/null || warn "logseq-publish.py not found"

  # Copy references
  for REF in "$SCRIPT_DIR/skills/hermes-logseq/references/"*; do
    [ -f "$REF" ] && cp "$REF" "$PARENT_DIR/references/"
  done

  ok "Skills installed to $HERMES_SKILLS_DIR/"
  echo ""
  info "Add to your Hermes agent config.yaml:"
  echo "  enabled_skillsets: [\"hermes-logseq\", \"hermes-logseq-viewer\", \"hermes-logseq-cron\"]"
  echo ""
}

# ─── Main ───

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detect_os
check_deps
check_pm2
interactive_setup
setup_logseqd
setup_inotify
if [ "$MODE" = "desktop" ]; then
  setup_git_watcher
fi
if [ "$INSTALL_VIEWER" = "yes" ]; then
  setup_viewer
fi
setup_skills

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "Verify logseqd:  curl http://localhost:$LOGSEQD_PORT/pages"
echo "Verify inotify:  pm2 logs logseq-inotify --lines 5"
if [ "$MODE" = "desktop" ]; then
echo "Verify git sync: pm2 logs logseq-git-watcher --lines 5"
fi
echo ""
echo "Skills installed. See ~/.hermes/skills/hermes-logseq/SKILL.md for usage."
echo ""
