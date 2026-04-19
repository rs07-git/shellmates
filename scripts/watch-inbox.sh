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
AGENT_PANE="${3:-}"   # The pane that ran the agent — included in ping so orchestrator can reuse it
INBOX_DIR="${HOME}/.shellmates/inbox"
RESULT_FILE="${INBOX_DIR}/${JOB_ID}.txt"
WARN_AFTER="${SHELLMATES_WARN_AFTER:-300}"   # warn orchestrator at 5 min
HARD_TIMEOUT="${SHELLMATES_TIMEOUT:-1800}"  # give up at 30 min
INTERVAL=1
ELAPSED=0
WARNED=false

if [[ -z "$JOB_ID" ]]; then
  echo "Usage: $0 JOB_ID [NOTIFY_PANE]"
  exit 1
fi

mkdir -p "$INBOX_DIR"

# Wait for the result file — send a warning at WARN_AFTER seconds but keep watching.
# Only give up at HARD_TIMEOUT (default 30 min).
while [[ ! -f "$RESULT_FILE" && $ELAPSED -lt $HARD_TIMEOUT ]]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  # At the warning threshold, ping the orchestrator once — agent is just taking longer
  if [[ "$WARNED" == "false" && $ELAPSED -ge $WARN_AFTER ]]; then
    WARNED=true
    WARN_MSG="SHELLMATES_WARN: job:${JOB_ID} still running after ${WARN_AFTER}s — agent active, no action needed"
    if [[ -n "$NOTIFY_PANE" ]]; then
      tmux send-keys -l -t "$NOTIFY_PANE" "$WARN_MSG" 2>/dev/null || true
      tmux send-keys -t "$NOTIFY_PANE" "" Enter 2>/dev/null || true
    fi
    echo "$WARN_MSG"
  fi
done

if [[ ! -f "$RESULT_FILE" ]]; then
  TIMEOUT_MSG="SHELLMATES_TIMEOUT: job:${JOB_ID} gave up after ${HARD_TIMEOUT}s — no result file written"
  if [[ -n "$NOTIFY_PANE" ]]; then
    tmux send-keys -l -t "$NOTIFY_PANE" "$TIMEOUT_MSG" 2>/dev/null || true
    tmux send-keys -t "$NOTIFY_PANE" "" Enter 2>/dev/null || true
  fi
  echo "$TIMEOUT_MSG"
  exit 1
fi

# Read the result
RESULT=$(cat "$RESULT_FILE")
SUMMARY=$(grep "^RESULT:" "$RESULT_FILE" -A 5 | tail -5 | tr '\n' ' ' | cut -c1-120)

# Build message — include agent pane ID so orchestrator can reuse it for the next plan
REUSE_HINT=""
[[ -n "$AGENT_PANE" ]] && REUSE_HINT=" reuse-pane:${AGENT_PANE}"
MSG="AGENT_PING: job:${JOB_ID}${REUSE_HINT} status:complete ${SUMMARY} — AWAITING_INSTRUCTIONS"

# Write to pending-pings immediately — persists if live delivery fails
# (e.g. orchestrator has a dialog open and can't receive keystrokes right now)
PING_DIR="${HOME}/.shellmates/pending-pings"
mkdir -p "$PING_DIR"
PING_FILE="${PING_DIR}/${JOB_ID}.txt"
echo "$MSG" > "$PING_FILE"

# Notify the orchestrator — wait for any open dialog to clear before sending
if [[ -n "$NOTIFY_PANE" ]]; then
  MAX_WAIT=120   # Wait up to 2 minutes for orchestrator to become free
  ELAPSED_WAIT=0

  while [[ $ELAPSED_WAIT -lt $MAX_WAIT ]]; do
    pane_content=$(tmux capture-pane -t "$NOTIFY_PANE" -p 2>/dev/null | tail -8)

    # Detect common Claude Code dialog / permission prompt patterns
    if echo "$pane_content" | grep -qiE "Allow tool|Approve|trust this|\(y/n\)|Yes/No|Deny|confirm|allow this|allow read|allow write|allow bash"; then
      echo "Orchestrator dialog open (${ELAPSED_WAIT}s) — waiting for it to close..."
      sleep 3
      ELAPSED_WAIT=$((ELAPSED_WAIT + 3))
      continue
    fi

    # Pane looks free — send using -l (literal) to avoid tmux interpreting
    # brackets or colons in the message as terminal escape sequences
    tmux send-keys -l -t "$NOTIFY_PANE" "$MSG" 2>/dev/null
    tmux send-keys -t "$NOTIFY_PANE" "" Enter 2>/dev/null
    echo "Ping delivered to pane $NOTIFY_PANE"
    rm -f "$PING_FILE"
    exit 2
  done

  echo "Orchestrator dialog persisted ${MAX_WAIT}s — ping queued at $PING_FILE"
  echo "(Orchestrator will drain it on next turn via: for f in ~/.shellmates/pending-pings/*.txt; do ...)"
fi

# Fallback: print to stdout (asyncRewake hook reads this)
echo "$MSG"
exit 2
