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
HARD_TIMEOUT="${SHELLMATES_TIMEOUT:-1800}"  # give up at 30 min
INTERVAL=1
ELAPSED=0

if [[ -z "$JOB_ID" ]]; then
  echo "Usage: $0 JOB_ID [NOTIFY_PANE]"
  exit 1
fi

mkdir -p "$INBOX_DIR"

# Wait silently until the result file appears. No intermediate notifications —
# agents running long tasks are not a problem, just a long task.
# Only give up at HARD_TIMEOUT (default 30 min).
while [[ ! -f "$RESULT_FILE" && $ELAPSED -lt $HARD_TIMEOUT ]]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
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

# compute_pane_inventory — snapshot of pane state across the session at the moment
# the orchestrator is about to make its next decision.
#
# Outputs a string like: " idle-panes:%15,%18 busy-panes:%16 free-slots:3"
# that gets appended to the AGENT_PING so the orchestrator knows exactly
# what capacity is available without polling.
#
# Idle detection: looks for the agent CLI's input prompt in the last 3 lines.
# Matches Claude Code ("Type your message"), Gemini ("❯ " or "Thinking..."),
# and Codex ("> " at end of line).
compute_pane_inventory() {
  local notify_pane="$1"

  # Resolve session name from orchestrator pane
  local session
  session=$(tmux display-message -p -t "$notify_pane" '#S' 2>/dev/null || echo "")
  [[ -z "$session" ]] && echo " free-slots:unknown" && return

  local idle_list="" busy_list="" agent_count=0

  while IFS='|' read -r pid dead; do
    # Skip the orchestrator pane itself
    [[ "$pid" == "$notify_pane" ]] && continue
    # Skip dead panes
    [[ "$dead" == "1" ]] && continue

    agent_count=$((agent_count + 1))

    local content
    content=$(tmux capture-pane -t "$pid" -p 2>/dev/null | tail -3)

    # Match idle prompt patterns for Claude Code, Gemini CLI, and Codex
    if echo "$content" | grep -qE "Type your message|❯ $|> $"; then
      idle_list="${idle_list:+$idle_list,}$pid"
    else
      busy_list="${busy_list:+$busy_list,}$pid"
    fi
  done < <(tmux list-panes -s -t "$session" -F '#{pane_id}|#{pane_dead}' 2>/dev/null)

  local free=$((6 - agent_count))
  [[ $free -lt 0 ]] && free=0

  local out=""
  [[ -n "$idle_list" ]] && out="${out} idle-panes:${idle_list}"
  [[ -n "$busy_list" ]] && out="${out} busy-panes:${busy_list}"
  out="${out} free-slots:${free}"

  echo "$out"
}

# Build message — include agent pane ID and pane inventory
REUSE_HINT=""
[[ -n "$AGENT_PANE" ]] && REUSE_HINT=" reuse-pane:${AGENT_PANE}"

INVENTORY=""
[[ -n "$NOTIFY_PANE" ]] && INVENTORY=$(compute_pane_inventory "$NOTIFY_PANE")

MSG="AGENT_PING: job:${JOB_ID}${REUSE_HINT} status:complete${INVENTORY} ${SUMMARY} — AWAITING_INSTRUCTIONS"

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
