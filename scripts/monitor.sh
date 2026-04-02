#!/usr/bin/env bash
# monitor.sh — Background watcher for sub-agent panes
#
# Watches one or more tmux panes and reports:
#   - PHASE_COMPLETE signals
#   - AWAITING_INSTRUCTIONS signals
#   - Error keywords (error, failed, crash, exception, traceback)
#   - New git commits
#
# Usage:
#   ./scripts/monitor.sh                          # Watch orchestra:0.0 (default)
#   ./scripts/monitor.sh orchestra:0.0            # Explicit pane target
#   ./scripts/monitor.sh full:0.0 full:0.2        # Watch multiple panes
#   ./scripts/monitor.sh --interval 10 full:0.0   # Custom poll interval (seconds)
#
# Run in background:
#   ./scripts/monitor.sh > /tmp/orchestra-monitor.log 2>&1 &
#   tail -f /tmp/orchestra-monitor.log

set -euo pipefail

INTERVAL=15
TARGETS=()
PROJECT_DIR="${PWD}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="$2"; shift 2 ;;
    --dir)      PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--interval N] [--dir path] [pane-target...]"
      echo "  Default pane: orchestra:0.0"
      exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

# Default target
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=("orchestra:0.0")
fi

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "Monitoring ${#TARGETS[@]} pane(s): ${TARGETS[*]}"
log "Poll interval: ${INTERVAL}s | Project: ${PROJECT_DIR}"
log "Press Ctrl+C to stop."
echo ""

# Track state per pane
declare -A LAST_STATE
declare -A LAST_COMMIT

for TARGET in "${TARGETS[@]}"; do
  LAST_STATE[$TARGET]=""
  LAST_COMMIT[$TARGET]=$(git -C "$PROJECT_DIR" log --oneline -1 --format="%H" 2>/dev/null || echo "")
done

while true; do
  for TARGET in "${TARGETS[@]}"; do
    # Capture last N lines of pane
    PANE_TAIL=$(tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -10) || {
      log "[$TARGET] WARNING: could not capture pane — is the session running?"
      continue
    }

    # Detect PHASE_COMPLETE
    if echo "$PANE_TAIL" | grep -q "PHASE_COMPLETE:"; then
      SIGNAL=$(echo "$PANE_TAIL" | grep "PHASE_COMPLETE:" | tail -1)
      if [[ "$SIGNAL" != "${LAST_STATE[$TARGET]:-}" ]]; then
        log "[$TARGET] >>> $SIGNAL"
        LAST_STATE[$TARGET]="$SIGNAL"
      fi
    fi

    # Detect AWAITING_INSTRUCTIONS
    if echo "$PANE_TAIL" | grep -q "AWAITING_INSTRUCTIONS"; then
      if [[ "${LAST_STATE[$TARGET]:-}" != "AWAITING" ]]; then
        log "[$TARGET] >>> Sub-agent idle — AWAITING_INSTRUCTIONS"
        LAST_STATE[$TARGET]="AWAITING"
      fi
    fi

    # Detect shell prompt (agent returned to shell — likely done or crashed)
    if echo "$PANE_TAIL" | grep -qE "\\\$ $|> $"; then
      if [[ "${LAST_STATE[$TARGET]:-}" != "SHELL" ]]; then
        log "[$TARGET] >>> Shell prompt detected — agent may have exited"
        LAST_STATE[$TARGET]="SHELL"
      fi
    fi

    # Detect errors
    if echo "$PANE_TAIL" | grep -qiE "(^error|failed:|crash|exception|traceback|SyntaxError)"; then
      log "[$TARGET] !!! POSSIBLE ERROR — last 15 lines:"
      tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -15 | sed "s/^/  [$TARGET] /"
    fi

    # Detect new git commits
    CURRENT_COMMIT=$(git -C "$PROJECT_DIR" log --oneline -1 --format="%H" 2>/dev/null || echo "")
    if [[ -n "$CURRENT_COMMIT" && "$CURRENT_COMMIT" != "${LAST_COMMIT[$TARGET]:-}" && -n "${LAST_COMMIT[$TARGET]:-}" ]]; then
      COMMIT_MSG=$(git -C "$PROJECT_DIR" log --oneline -1 2>/dev/null)
      log "[$TARGET] >>> NEW COMMIT: $COMMIT_MSG"
      LAST_COMMIT[$TARGET]="$CURRENT_COMMIT"
    elif [[ -z "${LAST_COMMIT[$TARGET]:-}" ]]; then
      LAST_COMMIT[$TARGET]="$CURRENT_COMMIT"
    fi
  done

  sleep "$INTERVAL"
done
