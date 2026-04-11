#!/usr/bin/env bash
# dispatch.sh — Reliably send a task to a sub-agent pane
#
# Fixes addressed:
#   1. Startup timing: waits for agent prompt to be ready before sending
#   2. Permission prompts: enables auto-edit mode (Shift+Tab) before dispatching
#   3. Token efficiency: prepends agent communication protocol header to every task
#   4. Completion notification: starts background watcher + writes to inbox file
#   5. Session visibility: shows or opens a live view of the worker after dispatch
#
# Usage:
#   bash scripts/dispatch.sh --pane %46 --task-file /tmp/task.txt
#   bash scripts/dispatch.sh --pane %46 --task "one-liner task"
#   bash scripts/dispatch.sh --pane orchestra:0.0 --task-file /tmp/task.txt --no-ping
#
# Options:
#   --pane        Target pane (stable %ID or positional session:0.0)
#   --task-file   Path to task file (preferred for multi-step tasks)
#   --task        Inline task (for simple one-liners)
#   --job-id      Job ID for inbox result file (default: auto-generated)
#   --ping-back   Pane to notify when done (default: caller's $TMUX_PANE)
#   --task-name   Short label for status display
#   --no-ping     Skip ping-back / inbox watcher (fire-and-forget)
#   --no-view     Don't show/open the session viewer after dispatch
#   --no-header   Skip prepending the agent communication protocol header

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADER_FILE="${SCRIPT_DIR}/../templates/task-header.txt"
INBOX_DIR="${HOME}/.shellmates/inbox"
PROJECT_TASKS_DIR=""   # set to project-relative path once we know the pane's cwd

PANE=""
TASK_FILE=""
TASK_INLINE=""
JOB_ID=""
PING_BACK_PANE=""
TASK_NAME=""
NO_PING=false
NO_VIEW=false
NO_HEADER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane)       PANE="$2"; shift 2 ;;
    --task-file)  TASK_FILE="$2"; shift 2 ;;
    --task)       TASK_INLINE="$2"; shift 2 ;;
    --job-id)     JOB_ID="$2"; shift 2 ;;
    --ping-back)  PING_BACK_PANE="$2"; shift 2 ;;
    --task-name)  TASK_NAME="$2"; shift 2 ;;
    --no-ping)    NO_PING=true; shift ;;
    --no-view)    NO_VIEW=true; shift ;;
    --no-header)  NO_HEADER=false; shift ;;  # reserved
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0 ;;
    *) echo "ERROR: Unknown option: $1"; exit 1 ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

if [[ -z "$PANE" ]]; then
  echo "ERROR: --pane is required"
  exit 1
fi

if [[ -z "$TASK_FILE" && -z "$TASK_INLINE" ]]; then
  echo "ERROR: --task-file or --task is required"
  exit 1
fi

# ── Resolve ping-back pane ────────────────────────────────────────────────────

if [[ -z "$PING_BACK_PANE" && "$NO_PING" == "false" ]]; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    PING_BACK_PANE="$TMUX_PANE"
  elif [[ -n "${TMUX:-}" ]]; then
    PING_BACK_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
  fi

  if [[ -z "$PING_BACK_PANE" ]]; then
    echo "NOTE: Not inside tmux — ping-back via tmux disabled."
    echo "  Inbox watcher will still write to ~/.shellmates/inbox/"
    echo "  Pass --ping-back PANE_ID to enable active notification."
  fi
fi

# ── Preflight: verify pane is running an agent ────────────────────────────────

PANE_CMD=$(tmux display-message -p -t "$PANE" '#{pane_current_command}' 2>/dev/null || echo "unknown")
SHELL_CMDS=("bash" "zsh" "sh" "fish")

for SHELL_CMD in "${SHELL_CMDS[@]}"; do
  if [[ "$PANE_CMD" == "$SHELL_CMD" ]]; then
    echo "ERROR: Pane $PANE is running $PANE_CMD — no agent detected."
    echo "  Start the agent first: tmux send-keys -t $PANE 'gemini' Enter"
    exit 1
  fi
done

echo "Target pane: $PANE (process: $PANE_CMD)"

# Resolve the pane's working directory (used to place task files inside the project)
PANE_CWD=$(tmux display-message -p -t "$PANE" '#{pane_current_path}' 2>/dev/null || echo "/tmp")
PROJECT_TASKS_DIR="${PANE_CWD}/.shellmates/tasks"

# ── Wait for agent prompt and dismiss startup banner ──────────────────────────
# Gemini shows a startup banner AFTER the initial prompt appears.
# If we send the task immediately after seeing "Type your message", the banner
# appears and steals the Enter keystroke — task never submits.
# Fix: explicitly detect and dismiss the banner before dispatching.

wait_for_prompt() {
  local pane="$1"
  local max_wait=20
  local elapsed=0
  echo -n "Waiting for agent prompt..."
  while [[ $elapsed -lt $max_wait ]]; do
    local output
    output=$(tmux capture-pane -t "$pane" -p 2>/dev/null)
    if echo "$output" | grep -q "Type your message"; then
      echo " ready."
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo " (timeout — proceeding anyway)"
}

dismiss_startup_banner() {
  local pane="$1"
  local output
  output=$(tmux capture-pane -t "$pane" -p 2>/dev/null)
  # Gemini shows an announcement banner with "What's Changing" or similar
  if echo "$output" | grep -qE "What's Changing|We're making changes|Read more:.*goo\.gle"; then
    echo "Dismissing startup banner..."
    tmux send-keys -t "$pane" "" Enter
    sleep 1
    # Wait for prompt to reappear after dismiss
    wait_for_prompt "$pane"
  fi
}

# Verify the pane's input bar contains the expected string.
# Returns 0 if found, 1 if not.
input_bar_contains() {
  local pane="$1"
  local expected="$2"
  tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qF "$expected"
}

# Ensure a string is in the input bar before submitting. If the banner
# cleared it (by consuming @filepath or the prior Enter), re-type it.
ensure_input_ready() {
  local pane="$1"
  local text="$2"
  local max_retries=3
  local attempt=0

  while [[ $attempt -lt $max_retries ]]; do
    if input_bar_contains "$pane" "$text"; then
      echo "Input verified: $(basename "$text" 2>/dev/null || echo "$text")"
      return 0
    fi

    attempt=$((attempt + 1))
    echo "Input bar missing expected text (attempt $attempt) — re-typing..."
    # Clear whatever might be half-typed and retype
    tmux send-keys -t "$pane" "C-c" 2>/dev/null || true
    sleep 0.2
    wait_for_prompt "$pane"
    dismiss_startup_banner "$pane"
    tmux send-keys -t "$pane" "$text"
    sleep 0.4
  done

  echo "WARNING: Could not verify input bar after $max_retries attempts — submitting anyway"
}

wait_for_prompt "$PANE"
dismiss_startup_banner "$PANE"

# ── Enable auto-edit mode if not already in bypass mode ──────────────────────
# If the agent was NOT started with --yolo/--full-auto (i.e. permission_mode=default),
# send Shift+Tab to at least enable auto-edit for this session (approves file tools).
# If bypass mode is active, the agent already handles this at startup — skip it.

CONFIG_FILE="${HOME}/.shellmates/config.json"
PERMISSION_MODE=$(python3 -c "
import json, os
cfg = '${CONFIG_FILE}'
if os.path.exists(cfg):
    d = json.load(open(cfg))
    print(d.get('permission_mode', 'default'))
else:
    print('default')
" 2>/dev/null || echo "default")

if [[ "$PERMISSION_MODE" != "bypass" ]]; then
  if [[ "$PANE_CMD" == "node" || "$PANE_CMD" == "gemini" ]]; then
    # Gemini: Shift+Tab toggles auto-edit (approves file read/write tools)
    tmux send-keys -t "$PANE" "BTab"
    sleep 0.3
  fi
fi

# ── Build final task file ─────────────────────────────────────────────────────

# Resolve inline task to file
TEMP_TASK_FILE=""
if [[ -n "$TASK_INLINE" ]]; then
  TEMP_TASK_FILE="/tmp/.shellmates-task-$$.txt"
  echo "$TASK_INLINE" > "$TEMP_TASK_FILE"
  TASK_FILE="$TEMP_TASK_FILE"
fi

# Auto-generate job ID
if [[ -z "$JOB_ID" ]]; then
  JOB_ID="job-$$-$(date +%s)"
fi

# Auto-generate task name
if [[ -z "$TASK_NAME" ]]; then
  TASK_NAME=$(grep -m1 '.' "$TASK_FILE" | sed 's/^#* *//' | cut -c1-60)
fi

# Build the final task: header + original task + completion footer
# Place the file INSIDE the project dir so agents don't need a separate
# permission prompt to read it (Gemini --yolo still prompts for /tmp reads).
mkdir -p "$PROJECT_TASKS_DIR" 2>/dev/null || true
if [[ -d "$PROJECT_TASKS_DIR" ]]; then
  FINAL_TASK_FILE="${PROJECT_TASKS_DIR}/.dispatch-$$.txt"
else
  FINAL_TASK_FILE="/tmp/.shellmates-dispatch-$$.txt"
fi
mkdir -p "$INBOX_DIR"

{
  # Token efficiency protocol header
  if [[ -f "$HEADER_FILE" ]]; then
    cat "$HEADER_FILE"
    echo ""
  fi

  # Original task content
  cat "$TASK_FILE"

  # Completion footer: write result to inbox file
  cat << FOOTER

---
When your task is complete, write your result to this file:
  ${INBOX_DIR}/${JOB_ID}.txt

Use this exact format (concise — no prose):
\`\`\`
AGENT: $(echo "$PANE_CMD" | tr '[:upper:]' '[:lower:]')
JOB: ${JOB_ID}
STATUS: complete
CHANGED: <comma-separated file paths, or none>
RESULT: <≤5 line summary of what was done>
\`\`\`

Write the file with:
  mkdir -p "${INBOX_DIR}" && cat > "${INBOX_DIR}/${JOB_ID}.txt" << 'EOF'
AGENT: gemini
JOB: ${JOB_ID}
STATUS: complete
CHANGED: <files>
RESULT: <summary>
EOF

Then output: PHASE_COMPLETE: ${TASK_NAME}
FOOTER
} > "$FINAL_TASK_FILE"

# Cleanup inline temp file
[[ -n "$TEMP_TASK_FILE" ]] && rm -f "$TEMP_TASK_FILE"

# ── Dispatch ──────────────────────────────────────────────────────────────────

if [[ "$PANE_CMD" == "node" || "$PANE_CMD" == "gemini" ]]; then
  echo "Dispatching via @filepath (Gemini CLI)..."
  # Type the filepath but don't submit yet — Gemini may re-show the startup
  # banner between the @filepath and the Enter. We:
  #   1. Type the @filepath (no Enter)
  #   2. Dismiss any banner that appeared
  #   3. Verify the input bar still contains the filepath (re-type if not)
  #   4. Submit
  tmux send-keys -t "$PANE" "@${FINAL_TASK_FILE}"
  sleep 0.5
  dismiss_startup_banner "$PANE"
  ensure_input_ready "$PANE" "@${FINAL_TASK_FILE}"
  tmux send-keys -t "$PANE" "" Enter
else
  echo "Dispatching via direct send..."
  tmux send-keys -t "$PANE" "$(cat "$FINAL_TASK_FILE")"
  tmux send-keys -t "$PANE" "" Enter
fi

echo "Task dispatched: '${TASK_NAME}'"
echo "Job ID: ${JOB_ID}"
echo "Result will appear in: ${INBOX_DIR}/${JOB_ID}.txt"

# ── Start background watcher ──────────────────────────────────────────────────

if [[ "$NO_PING" == "false" ]]; then
  WATCH_ARGS="$JOB_ID"
  [[ -n "$PING_BACK_PANE" ]] && WATCH_ARGS="$WATCH_ARGS $PING_BACK_PANE"

  bash "$SCRIPT_DIR/watch-inbox.sh" $WATCH_ARGS &
  WATCHER_PID=$!
  echo "Background watcher started (PID: $WATCHER_PID)"
fi

# ── Show session view ─────────────────────────────────────────────────────────

if [[ "$NO_VIEW" == "false" ]]; then
  SESSION=$(tmux display-message -p -t "$PANE" '#S' 2>/dev/null || echo "")
  if [[ -n "$SESSION" ]]; then
    echo ""
    bash "$SCRIPT_DIR/view-session.sh" "$SESSION" "$PANE"
  fi
fi

echo ""
echo "Task file: $FINAL_TASK_FILE"
echo "Monitor:   tmux capture-pane -t $PANE -p | tail -20"
