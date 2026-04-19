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
#   --workers     Number of parallel agents (1-6, default: 1)
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
REUSE_PANE=""

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
    --reuse-pane) REUSE_PANE="$2"; shift 2 ;;
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

if [[ "$WORKERS" -lt 1 || "$WORKERS" -gt 6 ]]; then
  echo "ERROR: --workers must be between 1 and 6"
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

# ── Window border helper ──────────────────────────────────────────────────────
#
# Applies consistent visual borders to every shellmates window:
#   • Dim gray border lines between panes (inactive)
#   • Bright blue border for the focused pane
#   • Heavy border lines (tmux 3.2+) for clearer separation
#   • Color-coded title strip at the top of each pane
#       orchestrator → green   executors → orange

setup_window_borders() {
  local target="$1"
  # Double lines give a more visually distinct separation than heavy single lines.
  # Bright yellow active border (colour226) is impossible to miss.
  # Inactive borders use colour244 (light grey) — visible but not distracting.
  tmux set-option -w -t "$target" pane-border-style        "fg=colour244"      2>/dev/null || true
  tmux set-option -w -t "$target" pane-active-border-style "fg=colour226,bold" 2>/dev/null || true
  tmux set-option -w -t "$target" pane-border-status       top                 2>/dev/null || true
  tmux set-option -w -t "$target" pane-border-lines        double              2>/dev/null || true
  tmux set-option -w -t "$target" pane-border-format \
    "#{?#{==:#{pane_title},orchestrator},#[fg=colour83 bold]  ◆ #{pane_title}  ,#[fg=colour214 bold]  ◇ #{pane_title}  }#[default]" \
    2>/dev/null || true
}

# ── Create pane / session ─────────────────────────────────────────────────────
#
# Pond layout (inside tmux):
#   ┌──────────────────┬────────────────────┐
#   │                  │   Executor 1       │  ← 1st spawn: split right
#   │   Orchestrator   ├────────────────────┤
#   │   (full height)  │   Executor 2       │  ← 2nd spawn: split bottom-right
#   └──────────────────┴────────────────────┘
#   3rd+ executor → new tmux window (Ctrl+B n to reach)
#
# Outside tmux: creates a normal detached session.

PANE_2=""
IN_NEW_WINDOW=false

if [[ -n "$REUSE_PANE" ]]; then
  # ── Reuse mode: clear context in a warm existing pane ────────────────────────
  # Skips agent startup entirely — /clear resets conversation in ~1s vs ~5s cold start.
  PANE_1="$REUSE_PANE"

  # Resolve session name for summary / manifest (use pane's existing session)
  if [[ -z "$SESSION" ]]; then
    SESSION=$(tmux display-message -p -t "$PANE_1" '#S' 2>/dev/null || echo "reused-$$")
  fi

  PANE_DEAD_CHECK=$(tmux display-message -p -t "$PANE_1" '#{pane_dead}' 2>/dev/null || echo "0")

  if [[ "$PANE_DEAD_CHECK" == "1" ]]; then
    # Agent process died — respawn shell and start fresh
    echo "Pane $PANE_1 process is dead — respawning..."
    tmux respawn-pane -k -t "$PANE_1" 2>/dev/null || true
    sleep 1
    _CFG="${HOME}/.shellmates/config.json"
    _PERM=$(python3 -c "import json,os; d=json.load(open('$_CFG')) if os.path.exists('$_CFG') else {}; print(d.get('permission_mode','default'))" 2>/dev/null || echo "default")
    if [[ "$_PERM" == "bypass" ]]; then
      case "$AGENT" in
        gemini) _ACMD="gemini --yolo" ;;
        codex)  _ACMD="codex --full-auto" ;;
        *)      _ACMD="$AGENT" ;;
      esac
    else
      _ACMD="$AGENT"
    fi
    tmux send-keys -t "$PANE_1" "$_ACMD" Enter
    sleep 3
  else
    echo "Reusing warm pane $PANE_1 — clearing context with /clear..."
    tmux send-keys -t "$PANE_1" "/clear" Enter
    _WAIT=0
    while [[ $_WAIT -lt 10 ]]; do
      sleep 1; _WAIT=$((_WAIT + 1))
      tmux capture-pane -t "$PANE_1" -p 2>/dev/null | grep -q "Type your message" && break
    done
    echo "Pane ready."
  fi

  tmux select-pane -t "$PANE_1" -T "$AGENT" 2>/dev/null || true

elif [[ "$INSIDE_TMUX" == "true" ]]; then
  PANE_COUNT=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | wc -l | tr -d ' ')

  if [[ $PANE_COUNT -eq 1 ]]; then
    # ── First executor: split right (orch left, agent right) ─────────────────
    ORCH_PANE=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | head -1)
    tmux split-window -h -t "$ORCH_PANE" -c "$PROJECT_DIR" -p 50
    PANE_1=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | tail -1)
    setup_window_borders "$PARENT_SESSION:0"
    tmux select-pane -t "$ORCH_PANE" -T "orchestrator" 2>/dev/null || true

  elif [[ $PANE_COUNT -eq 2 ]]; then
    # ── Second executor: split right pane vertically (top-right / bottom-right)
    RIGHT_PANE=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | tail -1)
    tmux split-window -v -t "$RIGHT_PANE" -c "$PROJECT_DIR"
    PANE_1=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | tail -1)

  elif [[ $PANE_COUNT -eq 3 ]]; then
    # ── Third executor: split bottom-right pane again (right column now has 3 rows)
    BOTTOM_RIGHT=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | tail -1)
    tmux split-window -v -t "$BOTTOM_RIGHT" -c "$PROJECT_DIR"
    PANE_1=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | tail -1)

  else
    # ── Main window full — place agent in an overflow window.
    #
    # Priority order (scans ALL agents* windows, not just the last one):
    #   1. Reuse a dead pane (process exited) via respawn-pane -k — no new window needed
    #   2. Split any agents* window that currently has only 1 pane
    #   3. Create a new agents-N window only when every existing one is full + alive
    #
    # This means a finished agent's slot is immediately available for the next spawn,
    # and gaps are filled before new windows are ever opened.
    IN_NEW_WINDOW=true
    PANE_1=""

    # Step 1: scan ALL agents* windows for a dead pane and respawn it
    while IFS= read -r WIN_NAME; do
      while IFS= read -r PANE_INFO; do
        PANE_ID="${PANE_INFO%%|*}"
        PANE_DEAD="${PANE_INFO##*|}"
        if [[ "$PANE_DEAD" == "1" ]]; then
          tmux respawn-pane -k -t "$PANE_ID" 2>/dev/null || true
          PANE_1="$PANE_ID"
          echo "  Reusing finished pane $PANE_ID in window '$WIN_NAME'"
          break 2
        fi
      done < <(tmux list-panes -t "$PARENT_SESSION:$WIN_NAME" \
        -F '#{pane_id}|#{pane_dead}' 2>/dev/null)
    done < <(tmux list-windows -t "$PARENT_SESSION" \
      -F '#{window_name}' 2>/dev/null | grep '^agents')

    # Step 2: find any agents* window with < 6 panes and add to it
    # Uses tiled layout so panes auto-arrange into a readable grid.
    if [[ -z "$PANE_1" ]]; then
      while IFS= read -r WIN_NAME; do
        OVF_PANE_COUNT=$(tmux list-panes -t "$PARENT_SESSION:$WIN_NAME" \
          -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
        if [[ $OVF_PANE_COUNT -lt 6 ]]; then
          ANY_PANE=$(tmux list-panes -t "$PARENT_SESSION:$WIN_NAME" \
            -F '#{pane_id}' | head -1)
          tmux split-window -t "$ANY_PANE" -c "$PROJECT_DIR"
          PANE_1=$(tmux list-panes -t "$PARENT_SESSION:$WIN_NAME" \
            -F '#{pane_id}' | tail -1)
          # Re-tile to keep panes evenly arranged
          tmux select-layout -t "$PARENT_SESSION:$WIN_NAME" tiled 2>/dev/null || true
          break
        fi
      done < <(tmux list-windows -t "$PARENT_SESSION" \
        -F '#{window_name}' 2>/dev/null | grep '^agents')
    fi

    # Step 3: every existing window is full and alive — open a new one
    if [[ -z "$PANE_1" ]]; then
      if ! tmux list-windows -t "$PARENT_SESSION" -F '#{window_name}' \
          2>/dev/null | grep -qx 'agents'; then
        NEW_WIN="agents"
      else
        WIN_NUM=2
        NEW_WIN="agents-$WIN_NUM"
        while tmux list-windows -t "$PARENT_SESSION" \
            -F '#{window_name}' 2>/dev/null | grep -qx "$NEW_WIN"; do
          WIN_NUM=$((WIN_NUM + 1))
          NEW_WIN="agents-$WIN_NUM"
        done
      fi
      tmux new-window -t "$PARENT_SESSION" -n "$NEW_WIN" -c "$PROJECT_DIR"
      setup_window_borders "$PARENT_SESSION:$NEW_WIN"
      PANE_1=$(tmux list-panes -t "$PARENT_SESSION:$NEW_WIN" \
        -F '#{pane_id}' | head -1)
      tmux select-layout -t "$PARENT_SESSION:$NEW_WIN" tiled 2>/dev/null || true
      echo "  Opened new overflow window: '$NEW_WIN'"
    fi

    tmux select-window -t "$PARENT_SESSION:0"
  fi

  # Label the agent pane and return focus to orchestrator pane
  tmux select-pane -t "$PANE_1" -T "$AGENT" 2>/dev/null || true
  if [[ "$IN_NEW_WINDOW" == "false" ]]; then
    ORCH_PANE=$(tmux list-panes -t "$PARENT_SESSION:0" -F '#{pane_id}' | head -1)
    tmux select-pane -t "$ORCH_PANE"
  fi

else
  # ── Outside tmux: create a normal detached session ────────────────────────
  tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR"
  setup_window_borders "$SESSION:0"
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

# Skip start_agent when reusing — the agent process is already running
if [[ -z "$REUSE_PANE" ]]; then
  start_agent "$PANE_1" "worker-1"
  if [[ "$WORKERS" -eq 2 ]]; then
    start_agent "$PANE_2" "worker-2"
  fi
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
  if [[ -n "$REUSE_PANE" ]]; then
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  Task dispatched to existing pane           │"
    echo "  │  Context cleared — reusing warm terminal    │"
    echo "  │  Pane: $REUSE_PANE                          │"
    echo "  └─────────────────────────────────────────────┘"
  elif [[ "$IN_NEW_WINDOW" == "true" ]]; then
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  Agent opened in a new window               │"
    echo "  │  Ctrl+B n  → jump to agent window          │"
    echo "  │  Ctrl+B p  → back to orchestrator          │"
    echo "  └─────────────────────────────────────────────┘"
  else
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │  Agent pane added to this window            │"
    echo "  │  Ctrl+B ←→ → move between panes            │"
    echo "  │  Ctrl+B z  → zoom a pane to full screen    │"
    echo "  └─────────────────────────────────────────────┘"
  fi
else
  bash "$SCRIPT_DIR/view-session.sh" "$SESSION" "$PANE_1"
fi

if [[ "$NO_PING" == "false" && -n "$PING_BACK_PANE" ]]; then
  echo "Agent will notify pane $PING_BACK_PANE when done."
fi

if [[ "$ATTACH" == "true" && "$INSIDE_TMUX" == "false" ]]; then
  tmux attach-session -t "$SESSION"
fi
