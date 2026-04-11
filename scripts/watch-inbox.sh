#!/usr/bin/env bash
# watch-inbox.sh — Background watcher for shellmates completion files
#
# Watches ~/.shellmates/inbox/ for result files. When one appears,
# notifies the orchestrator (Claude) either via:
#   - tmux send-keys (if orchestrator is in a tmux pane)
#   - stdout (if orchestrator is polling or using asyncRewake hook)
#
# This is intended to run as a background process started by dispatch.sh.
# When a result arrives, it wakes Claude automatically — no manual polling.
#
# Usage:
#   bash scripts/watch-inbox.sh JOB_ID [NOTIFY_PANE]
#
#   JOB_ID       Unique ID for this job (matches the result filename)
#   NOTIFY_PANE  tmux pane to notify (e.g. %47). If omitted, uses $TMUX_PANE.
#
# Exit codes (for asyncRewake hook integration):
#   0  — completed cleanly (no asyncRewake)
#   2  — result received (triggers asyncRewake if used as a hook)

set -euo pipefail

JOB_ID="${1:-}"
NOTIFY_PANE="${2:-${TMUX_PANE:-}}"
INBOX_DIR="${HOME}/.shellmates/inbox"
RESULT_FILE="${INBOX_DIR}/${JOB_ID}.txt"
TIMEOUT="${SHELLMATES_TIMEOUT:-300}"  # 5 minutes default
INTERVAL=1
ELAPSED=0

if [[ -z "$JOB_ID" ]]; then
  echo "Usage: $0 JOB_ID [NOTIFY_PANE]"
  exit 1
fi

mkdir -p "$INBOX_DIR"

# Wait for the result file
while [[ ! -f "$RESULT_FILE" && $ELAPSED -lt $TIMEOUT ]]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ ! -f "$RESULT_FILE" ]]; then
  MSG="SHELLMATES_TIMEOUT: job $JOB_ID timed out after ${TIMEOUT}s"
  if [[ -n "$NOTIFY_PANE" ]]; then
    tmux send-keys -t "$NOTIFY_PANE" "$MSG — AWAITING_INSTRUCTIONS" Enter 2>/dev/null || true
  fi
  echo "$MSG"
  exit 1
fi

# Read the result
RESULT=$(cat "$RESULT_FILE")
SUMMARY=$(grep "^RESULT:" "$RESULT_FILE" -A 5 | tail -5 | tr '\n' ' ' | cut -c1-120)

MSG="AGENT_PING: job:${JOB_ID} status:complete ${SUMMARY} — AWAITING_INSTRUCTIONS"

# Notify the orchestrator
if [[ -n "$NOTIFY_PANE" ]]; then
  # Active notification: type directly into orchestrator's pane
  tmux send-keys -t "$NOTIFY_PANE" "$MSG" Enter 2>/dev/null && {
    echo "Notified pane $NOTIFY_PANE"
    exit 2  # asyncRewake signal
  }
fi

# Fallback: print to stdout (orchestrator polling or asyncRewake hook reads this)
echo "$MSG"
exit 2
