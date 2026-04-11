#!/usr/bin/env bash
# view-session.sh — Open a live view of a shellmates worker session
#
# Handles three cases automatically:
#   1. User is inside tmux → creates a new window in their session
#   2. User is on macOS, not in tmux → opens iTerm2 or Terminal.app
#   3. Fallback → prints the attach command prominently
#
# Usage:
#   bash scripts/view-session.sh SESSION_NAME [PANE_ID]
#   bash scripts/view-session.sh --list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List mode
if [[ "${1:-}" == "--list" ]]; then
  bash "$SCRIPT_DIR/status.sh"
  exit 0
fi

SESSION="${1:-}"
PANE="${2:-}"

if [[ -z "$SESSION" ]]; then
  echo "Usage: $0 SESSION_NAME"
  echo "       $0 --list     # show all active sessions"
  exit 1
fi

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERROR: Session '$SESSION' not found."
  echo "Active sessions:"
  tmux list-sessions -F "  #{session_name}" 2>/dev/null || echo "  (none)"
  exit 1
fi

# ── Case 1: Already inside tmux ───────────────────────────────────────────────
if [[ -n "${TMUX:-}" ]]; then
  CURRENT_SESSION=$(tmux display-message -p '#S')

  # If the worker is already in our session, just switch to it
  if [[ "$SESSION" == "$CURRENT_SESSION" ]]; then
    if [[ -n "$PANE" ]]; then
      tmux select-pane -t "$PANE"
      echo "Switched to pane $PANE in current session."
    else
      echo "Already in session '$SESSION' — use Ctrl+b [arrow] to navigate panes."
    fi
    exit 0
  fi

  # Worker is in a different session — open it in a new window
  tmux new-window -t "$CURRENT_SESSION" \; \
    send-keys -t "$CURRENT_SESSION" "tmux attach -t $SESSION" Enter
  echo "Opened '$SESSION' in a new tmux window."
  echo "Navigate: Ctrl+b n (next window) / Ctrl+b p (prev window)"
  exit 0
fi

# ── Case 2: macOS, not in tmux — try to open a terminal window ───────────────
if command -v osascript &>/dev/null; then
  # Try iTerm2 first (common for developers)
  if osascript -e 'tell application "iTerm2" to get version' &>/dev/null 2>&1; then
    osascript << APPLESCRIPT
tell application "iTerm2"
  activate
  create window with default profile
  tell current session of current window
    write text "tmux attach -t $SESSION"
  end tell
end tell
APPLESCRIPT
    echo "Opened '$SESSION' in a new iTerm2 window."
    exit 0
  fi

  # Try Terminal.app
  if osascript -e 'tell application "Terminal" to get version' &>/dev/null 2>&1; then
    osascript -e "tell application \"Terminal\" to do script \"tmux attach -t $SESSION\""
    osascript -e 'tell application "Terminal" to activate'
    echo "Opened '$SESSION' in a new Terminal.app window."
    exit 0
  fi
fi

# ── Case 3: Fallback — print prominently ─────────────────────────────────────
CMD="tmux attach -t $SESSION"
BORDER=$(printf '═%.0s' $(seq 1 $((${#CMD} + 6))))

echo ""
echo "  ╔${BORDER}╗"
echo "  ║   ${CMD}   ║"
echo "  ╚${BORDER}╝"
echo ""
echo "  Run the command above in a new terminal to watch your agents work."
echo ""
