#!/usr/bin/env bash
# dispatch.sh — Reliably send a task to a sub-agent pane
#
# Fixes the multiline paste bug: uses @filepath (Gemini native) instead of
# send-keys with $(cat file). Automatically appends the AGENT_PING instruction
# so the sub-agent notifies the orchestrator when done — no polling needed.
#
# Usage:
#   bash scripts/dispatch.sh --pane %46 --task-file /tmp/task.txt
#   bash scripts/dispatch.sh --pane %46 --task "Describe what to do in one line"
#   bash scripts/dispatch.sh --pane orchestra:0.0 --task-file /tmp/task.txt --ping-back %47
#
# Options:
#   --pane        Target pane (stable pane ID like %46, or positional like orchestra:0.0)
#   --task-file   Path to task file (preferred — supports multiline)
#   --task        Inline task string (one-liners only — use --task-file for longer tasks)
#   --ping-back   Pane ID the sub-agent should ping when done (defaults to caller's pane)
#   --task-name   Short name for the AGENT_PING message (defaults to first line of task)
#   --no-ping     Skip the ping-back instruction (for fire-and-forget tasks)

set -euo pipefail

PANE=""
TASK_FILE=""
TASK_INLINE=""
PING_BACK_PANE=""
TASK_NAME=""
NO_PING=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane)       PANE="$2"; shift 2 ;;
    --task-file)  TASK_FILE="$2"; shift 2 ;;
    --task)       TASK_INLINE="$2"; shift 2 ;;
    --ping-back)  PING_BACK_PANE="$2"; shift 2 ;;
    --task-name)  TASK_NAME="$2"; shift 2 ;;
    --no-ping)    NO_PING=true; shift ;;
    -h|--help)
      echo "Usage: $0 --pane PANE_ID [--task-file FILE | --task TEXT] [--ping-back PANE] [--task-name NAME] [--no-ping]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate required args
if [[ -z "$PANE" ]]; then
  echo "ERROR: --pane is required"
  exit 1
fi

if [[ -z "$TASK_FILE" && -z "$TASK_INLINE" ]]; then
  echo "ERROR: either --task-file or --task is required"
  exit 1
fi

# Determine ping-back pane (caller's pane by default when running inside tmux)
if [[ -z "$PING_BACK_PANE" && "$NO_PING" == "false" ]]; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    PING_BACK_PANE="$TMUX_PANE"
  elif [[ -n "${TMUX:-}" ]]; then
    PING_BACK_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
  fi

  if [[ -z "$PING_BACK_PANE" ]]; then
    echo "WARNING: Not running inside tmux — cannot auto-detect ping-back pane."
    echo "  Pass --ping-back PANE_ID to enable AGENT_PING, or use --no-ping."
    NO_PING=true
  fi
fi

# Preflight: verify the target pane is running an agent, not a bare shell
PANE_CMD=$(tmux display-message -p -t "$PANE" '#{pane_current_command}' 2>/dev/null || echo "unknown")
SHELL_CMDS=("bash" "zsh" "sh" "fish")

for SHELL_CMD in "${SHELL_CMDS[@]}"; do
  if [[ "$PANE_CMD" == "$SHELL_CMD" ]]; then
    echo "ERROR: Pane $PANE is running $PANE_CMD, not an AI agent."
    echo "  Start the agent first: tmux send-keys -t $PANE 'gemini' Enter"
    echo "  Then re-run this command."
    exit 1
  fi
done

echo "Target pane: $PANE (process: $PANE_CMD)"

# Resolve task content
TEMP_TASK_FILE=""
if [[ -n "$TASK_INLINE" ]]; then
  TEMP_TASK_FILE="/tmp/.shellmates-task-$$.txt"
  echo "$TASK_INLINE" > "$TEMP_TASK_FILE"
  TASK_FILE="$TEMP_TASK_FILE"
fi

# Get task name from first non-empty line if not set
if [[ -z "$TASK_NAME" ]]; then
  TASK_NAME=$(grep -m1 '.' "$TASK_FILE" | sed 's/^#* *//' | cut -c1-60)
fi

# Append AGENT_PING instruction to the task (unless --no-ping)
FINAL_TASK_FILE="/tmp/.shellmates-dispatch-$$.txt"

if [[ "$NO_PING" == "false" ]]; then
  cat "$TASK_FILE" > "$FINAL_TASK_FILE"
  cat >> "$FINAL_TASK_FILE" << PING_FOOTER

---
**IMPORTANT — when your task is complete, run this exact bash command to notify the orchestrator:**
\`\`\`bash
tmux send-keys -t $PING_BACK_PANE "AGENT_PING: ${TASK_NAME} complete. [brief summary of what was done and any issues]. — AWAITING_INSTRUCTIONS" Enter
\`\`\`
Do NOT just output AGENT_PING to your own terminal — the orchestrator cannot see your stdout.
You must run the tmux command above so it physically appears in the orchestrator's pane.
PING_FOOTER
else
  cp "$TASK_FILE" "$FINAL_TASK_FILE"
fi

# Cleanup inline temp file
[[ -n "$TEMP_TASK_FILE" ]] && rm -f "$TEMP_TASK_FILE"

# Detect agent type from pane process and dispatch accordingly
if [[ "$PANE_CMD" == "node" || "$PANE_CMD" == "gemini" ]]; then
  # Gemini CLI: use @filepath syntax (single line, always submits correctly)
  echo "Dispatching via @filepath (Gemini CLI)..."
  tmux send-keys -t "$PANE" "@${FINAL_TASK_FILE}" Enter

elif [[ "$PANE_CMD" == "node" ]]; then
  # Codex CLI also runs as node — use same approach
  echo "Dispatching via @filepath (Codex CLI)..."
  tmux send-keys -t "$PANE" "@${FINAL_TASK_FILE}" Enter

else
  # Claude Code or unknown: send directly (Claude handles multiline paste reliably)
  echo "Dispatching via direct send (Claude Code / unknown agent)..."
  tmux send-keys -t "$PANE" "$(cat "$FINAL_TASK_FILE")"
  tmux send-keys -t "$PANE" "" Enter
fi

echo "Task dispatched: '${TASK_NAME}'"
if [[ "$NO_PING" == "false" ]]; then
  echo "Agent will ping back to pane $PING_BACK_PANE when done."
fi

# Note: don't delete FINAL_TASK_FILE — the agent may read it asynchronously via @filepath
echo ""
echo "Task file: $FINAL_TASK_FILE"
echo "Monitor:   tmux capture-pane -t $PANE -p | tail -20"
