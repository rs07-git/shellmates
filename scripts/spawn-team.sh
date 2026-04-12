#!/usr/bin/env bash
# spawn-team.sh — Spawn an agent team and delegate a task in one command
#
# This is the frictionless interface to shellmates.
# Tell it what you want done — it handles session creation, agent startup,
# task dispatch, and ping-back. No tmux knowledge required.
#
# Usage:
#   bash scripts/spawn-team.sh --task "check GSD status" --project ~/Projects
#   bash scripts/spawn-team.sh --task-file /tmp/my-task.txt --agent codex
#   bash scripts/spawn-team.sh --task "run phase 3" --workers 2
#
# The agent will notify your current pane when done via AGENT_PING.
# You don't need to poll — just wait for the ping to appear.
#
# Options:
#   --task        Inline task description
#   --task-file   Path to detailed task file (preferred for multi-step tasks)
#   --agent       Agent type: gemini (default) or codex
#   --workers     Number of parallel agents (1-2, default: 1)
#   --project     Project directory (default: current working directory)
#   --session     Session name (default: auto-generated from timestamp)
#   --purpose     Short label shown in status.sh (default: first line of task)
#   --ping-back   Pane ID to notify when done (default: your current pane)
#   --no-ping     Don't send AGENT_PING (fire-and-forget mode)
#   --attach      Attach to the new session after launching (default: no)
#   -h|--help     Show this help

set -euo pipefail

TASK_INLINE=""
TASK_FILE=""
AGENT="gemini"
WORKERS=1
PROJECT_DIR="${PWD}"
SESSION=""
PURPOSE=""
PING_BACK_PANE=""
NO_PING=false
ATTACH=false

# Detect if we're running inside an existing tmux session (e.g. a pond session).
# If so, open agents as windows in the current session instead of new detached sessions.
INSIDE_TMUX=false
PARENT_SESSION=""
if [[ -n "${TMUX:-}" ]]; then
  INSIDE_TMUX=true
  PARENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${HOME}/.shellmates"
MANIFEST_FILE="${MANIFEST_DIR}/sessions.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)       TASK_INLINE="$2"; shift 2 ;;
    --task-file)  TASK_FILE="$2"; shift 2 ;;
    --agent)      AGENT="$2"; shift 2 ;;
    --workers)    WORKERS="$2"; shift 2 ;;
    --project)    PROJECT_DIR="$2"; shift 2 ;;
    --session)    SESSION="$2"; shift 2 ;;
    --purpose)    PURPOSE="$2"; shift 2 ;;
    --ping-back)  PING_BACK_PANE="$2"; shift 2 ;;
    --no-ping)    NO_PING=true; shift ;;
    --no-view)    ATTACH=false; shift ;;
    --attach)     ATTACH=true; shift ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0 ;;
    *) echo "ERROR: Unknown option: $1"; exit 1 ;;
  esac
done

# Validate input
if [[ -z "$TASK_INLINE" && -z "$TASK_FILE" ]]; then
  echo "ERROR: Provide --task or --task-file"
  echo "  Example: $0 --task \"check GSD status\" --project ~/Projects"
  exit 1
fi

if [[ -n "$TASK_FILE" && ! -f "$TASK_FILE" ]]; then
  echo "ERROR: Task file not found: $TASK_FILE"
  exit 1
fi

if [[ "$WORKERS" -lt 1 || "$WORKERS" -gt 2 ]]; then
  echo "ERROR: --workers must be 1 or 2"
  exit 1
fi

# Resolve project dir
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Auto-generate session name from timestamp if not provided
if [[ -z "$SESSION" ]]; then
  SESSION="team-$(date +%H%M%S)"
fi

# Auto-detect purpose from first line of task
if [[ -z "$PURPOSE" ]]; then
  if [[ -n "$TASK_FILE" ]]; then
    PURPOSE=$(grep -m1 '.' "$TASK_FILE" | sed 's/^#* *//' | cut -c1-50)
  else
    PURPOSE=$(echo "$TASK_INLINE" | head -1 | cut -c1-50)
  fi
fi

# Resolve ping-back pane
if [[ -z "$PING_BACK_PANE" && "$NO_PING" == "false" ]]; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    PING_BACK_PANE="$TMUX_PANE"
  elif [[ -n "${TMUX:-}" ]]; then
    PING_BACK_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
  fi

  if [[ -z "$PING_BACK_PANE" ]]; then
    echo "NOTE: Not running inside tmux — ping-back disabled."
    echo "  You'll need to poll the agent pane manually to check progress."
    echo "  Or use --ping-back PANE_ID to specify where to send the completion notification."
    NO_PING=true
  fi
fi

# Check for existing session (only relevant when creating a new detached session)
if [[ "$INSIDE_TMUX" == "false" ]] && tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERROR: Session '$SESSION' already exists."
  echo "  Use a different name: --session my-task-name"
  echo "  Or check existing: bash $SCRIPT_DIR/status.sh"
  exit 1
fi

# Check agent is available
if ! command -v "$AGENT" &>/dev/null; then
  echo "ERROR: '$AGENT' not found."
  [[ "$AGENT" == "gemini" ]] && echo "  Install: npm install -g @google/gemini-cli"
  [[ "$AGENT" == "codex" ]]  && echo "  Install: npm install -g @openai/codex"
  exit 1
fi

echo "Spawning team: $SESSION"
echo "  Agent:   $AGENT × $WORKERS"
echo "  Project: $PROJECT_DIR"
echo "  Task:    $PURPOSE"
[[ "$NO_PING" == "false" ]] && echo "  Ping:    $PING_BACK_PANE"
echo ""

# ── Create session (or window if already inside tmux) ────────────────────────

PANE_2=""
if [[ "$INSIDE_TMUX" == "true" ]]; then
  # Inside a pond session — open agent directly as a new window in this session.
  # No attach tricks, no separate sessions. User presses Ctrl+B n to reach it.
  WINDOW_NAME="$AGENT"
  tmux new-window -t "$PARENT_SESSION" -n "$WINDOW_NAME" -c "$PROJECT_DIR"
  PANE_1=$(tmux list-panes -t "$PARENT_SESSION:$WINDOW_NAME" -F '#{pane_id}' | sed -n '1p')
  tmux select-pane -t "$PANE_1" -T "worker-1 ($AGENT)" 2>/dev/null || true
  if [[ "$WORKERS" -eq 2 ]]; then
    tmux split-window -h -t "$PARENT_SESSION:$WINDOW_NAME" -c "$PROJECT_DIR"
    tmux select-layout -t "$PARENT_SESSION:$WINDOW_NAME" even-horizontal
    PANE_2=$(tmux list-panes -t "$PARENT_SESSION:$WINDOW_NAME" -F '#{pane_id}' | sed -n '2p')
    tmux select-pane -t "$PANE_2" -T "worker-2 ($AGENT)" 2>/dev/null || true
  fi
  # Return focus to the orchestrator window so Claude's output stays visible
  tmux select-window -t "$PARENT_SESSION:0"
else
  # Not inside tmux — create a normal detached session
  tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR"
  tmux set-option -w -t "$SESSION:0" pane-border-status top 2>/dev/null || true
  PANE_1=$(tmux list-panes -t "$SESSION:0" -F '#{pane_id}' | sed -n '1p')
  tmux select-pane -t "$PANE_1" -T "worker-1 ($AGENT)"
  if [[ "$WORKERS" -eq 2 ]]; then
    tmux split-window -h -t "$SESSION:0" -c "$PROJECT_DIR"
    tmux select-layout -t "$SESSION:0" even-horizontal
    PANE_2=$(tmux list-panes -t "$SESSION:0" -F '#{pane_id}' | sed -n '2p')
    tmux select-pane -t "$PANE_2" -T "worker-2 ($AGENT)"
  fi
fi

# ── Start agents ─────────────────────────────────────────────────────────────

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

agent_start_cmd() {
  local agent="$1"
  if [[ "$PERMISSION_MODE" == "bypass" ]]; then
    case "$agent" in
      gemini) echo "gemini --yolo" ;;
      codex)  echo "codex --full-auto" ;;
      *)      echo "$agent" ;;
    esac
  else
    echo "$agent"
  fi
}

start_agent() {
  local pane="$1"
  local label="$2"
  local cmd
  cmd=$(agent_start_cmd "$AGENT")
  echo -n "Starting $cmd in $label..."
  tmux send-keys -t "$pane" "$cmd" Enter

  # Wait until the agent prompt is visible (not just process started)
  local elapsed=0
  while [[ $elapsed -lt 15 ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
    local cmd
    cmd=$(tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || echo "unknown")
    if [[ "$cmd" != "bash" && "$cmd" != "zsh" && "$cmd" != "sh" && "$cmd" != "fish" ]]; then
      # Process is an agent — now wait for the prompt to appear
      if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -q "Type your message"; then
        echo " ready ($cmd)"
        return 0
      fi
    fi
  done

  # Timeout — show what we got
  local cmd
  cmd=$(tmux display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || echo "unknown")
  if [[ "$cmd" == "bash" || "$cmd" == "zsh" || "$cmd" == "sh" ]]; then
    echo " WARNING: agent may not have started (still $cmd)"
  else
    echo " OK ($cmd — prompt not yet visible)"
  fi
}

start_agent "$PANE_1" "worker-1"

if [[ "$WORKERS" -eq 2 ]]; then
  start_agent "$PANE_2" "worker-2"
fi

# ── Register in manifest ──────────────────────────────────────────────────────

mkdir -p "$MANIFEST_DIR"
LAUNCHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
ALL_PANES="\"worker-1\": \"$PANE_1\""
[[ -n "$PANE_2" ]] && ALL_PANES="$ALL_PANES, \"worker-2\": \"$PANE_2\""

python3 - <<PYEOF
import json, os

manifest_file = "$MANIFEST_FILE"
panes = {"worker-1": "$PANE_1"}
if "$PANE_2":
    panes["worker-2"] = "$PANE_2"

entry = {
    "name": "$SESSION",
    "purpose": "$PURPOSE",
    "project_dir": "$PROJECT_DIR",
    "agents": ["$AGENT"] * $WORKERS,
    "launched_at": "$LAUNCHED_AT",
    "panes": panes
}

if os.path.exists(manifest_file):
    with open(manifest_file) as f:
        data = json.load(f)
else:
    data = {"sessions": []}

data["sessions"] = [s for s in data["sessions"] if s["name"] != "$SESSION"]
data["sessions"].append(entry)

with open(manifest_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

# ── Dispatch task ─────────────────────────────────────────────────────────────

echo ""
echo "Dispatching task to worker-1..."

DISPATCH_ARGS="--pane $PANE_1 --no-view"  # spawn-team handles view itself

if [[ -n "$TASK_FILE" ]]; then
  DISPATCH_ARGS="$DISPATCH_ARGS --task-file $TASK_FILE"
else
  INLINE_TASK_FILE="/tmp/.shellmates-spawn-$$.txt"
  echo "$TASK_INLINE" > "$INLINE_TASK_FILE"
  DISPATCH_ARGS="$DISPATCH_ARGS --task-file $INLINE_TASK_FILE"
fi

if [[ "$NO_PING" == "true" ]]; then
  DISPATCH_ARGS="$DISPATCH_ARGS --no-ping"
elif [[ -n "$PING_BACK_PANE" ]]; then
  DISPATCH_ARGS="$DISPATCH_ARGS --ping-back $PING_BACK_PANE"
fi

DISPATCH_ARGS="$DISPATCH_ARGS --task-name $SESSION"
# shellcheck disable=SC2086
bash "$SCRIPT_DIR/dispatch.sh" $DISPATCH_ARGS

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Agent spawned: $SESSION"
echo ""

if [[ "$INSIDE_TMUX" == "true" ]]; then
  echo "  ┌─────────────────────────────────────────────┐"
  echo "  │  Agent is running in this session           │"
  echo "  │  Ctrl+B n  → switch to agent window        │"
  echo "  │  Ctrl+B p  → switch back to orchestrator   │"
  echo "  │  Ctrl+B w  → pick from window list         │"
  echo "  └─────────────────────────────────────────────┘"
else
  bash "$SCRIPT_DIR/view-session.sh" "$SESSION" "$PANE_1"
fi

if [[ "$NO_PING" == "false" && -n "$PING_BACK_PANE" ]]; then
  echo "Agent will notify pane $PING_BACK_PANE when done."
fi

if [[ "$ATTACH" == "true" && "$INSIDE_TMUX" == "false" ]]; then
  tmux attach-session -t "$SESSION"
fi
