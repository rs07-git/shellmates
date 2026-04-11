#!/usr/bin/env bash
# shellmates-notify.sh — Claude Code PostToolUse hook
#
# Fires after every Bash tool call. If the command was a shellmates dispatch,
# waits for the inbox result and exits with code 2 (asyncRewake) so Claude
# Code delivers the result as a native notification — no polling needed.
#
# Install:
#   cp templates/hooks/shellmates-notify.sh ~/.claude/hooks/
#   chmod +x ~/.claude/hooks/shellmates-notify.sh
#   Merge templates/hooks/settings-addition.json into ~/.claude/settings.json

set -euo pipefail

INBOX_DIR="${HOME}/.shellmates/inbox"
TIMEOUT="${SHELLMATES_TIMEOUT:-300}"

# Hook receives { tool_name, tool_input, tool_response } as JSON on stdin
INPUT=$(cat)

# Only act on Bash tool calls that used shellmates
COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
cmd = data.get('tool_input', {}).get('command', '')
print(cmd)
" 2>/dev/null || echo "")

if ! echo "$COMMAND" | grep -qE "shellmates spawn|spawn-team\.sh|dispatch\.sh"; then
  exit 0  # Not a shellmates dispatch — do nothing
fi

# Extract job ID from tool output (dispatch.sh prints "Job ID: job-XXXX")
TOOL_OUTPUT=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_response', {}).get('output', ''))
" 2>/dev/null || echo "")

JOB_ID=$(echo "$TOOL_OUTPUT" | grep -oE 'job-[0-9]+-[0-9]+' | head -1)

mkdir -p "$INBOX_DIR"

# Snapshot files before waiting
BEFORE=$(ls "$INBOX_DIR" 2>/dev/null | sort)

elapsed=0
while [[ $elapsed -lt $TIMEOUT ]]; do
  sleep 2
  elapsed=$((elapsed + 2))

  AFTER=$(ls "$INBOX_DIR" 2>/dev/null | sort)
  NEW=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep '\.txt$' | head -1)

  # If we have a specific job ID, wait for that file; otherwise take any new file
  if [[ -n "$JOB_ID" ]]; then
    TARGET="${INBOX_DIR}/${JOB_ID}.txt"
    [[ -f "$TARGET" ]] && NEW="${JOB_ID}.txt"
  fi

  if [[ -n "$NEW" ]]; then
    RESULT_FILE="${INBOX_DIR}/${NEW}"
    CONTENT=$(cat "$RESULT_FILE" 2>/dev/null || echo "result file unreadable")
    STATUS=$(echo "$CONTENT" | grep '^STATUS:' | cut -d: -f2- | xargs)
    RESULT=$(echo "$CONTENT" | grep '^RESULT:' | cut -d: -f2- | xargs)
    AGENT=$(echo "$CONTENT" | grep '^AGENT:' | cut -d: -f2- | xargs)

    # Print notification — Claude Code will surface this when asyncRewake fires
    echo "AGENT_PING: ${AGENT:-agent} finished. STATUS: ${STATUS:-complete}. RESULT: ${RESULT:-see inbox}. File: ${NEW}"

    # Exit code 2 = asyncRewake — Claude Code re-enqueues this as a task notification
    exit 2
  fi
done

echo "AGENT_PING: timeout after ${TIMEOUT}s — check ~/.shellmates/inbox/ manually"
exit 2
