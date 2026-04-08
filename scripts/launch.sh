#!/usr/bin/env bash
# launch.sh — Start or restore the shellmates session
#
# Usage:
#   ./scripts/launch.sh                             # 2-pane: Gemini + Claude
#   ./scripts/launch.sh --codex                     # 2-pane: Codex + Claude
#   ./scripts/launch.sh --session myname            # Custom session name (default: orchestra)
#   ./scripts/launch.sh --purpose "phase 3 work"   # Describe what this session is for
#
# Pane layout:
#   0.0  — Sub-agent (Gemini CLI or Codex CLI)
#   0.1  — Orchestrator (Claude Code)

set -euo pipefail

SESSION="orchestra"
SUB_AGENT="gemini"   # "gemini" or "codex"
PROJECT_DIR="${PWD}"
PURPOSE=""
MANIFEST_DIR="${HOME}/.shellmates"
MANIFEST_FILE="${MANIFEST_DIR}/sessions.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex)     SUB_AGENT="codex"; shift ;;
    --session)   SESSION="$2"; shift 2 ;;
    --dir)       PROJECT_DIR="$2"; shift 2 ;;
    --purpose)   PURPOSE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--codex] [--session name] [--dir path] [--purpose \"description\"]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Default purpose if not provided
if [[ -z "$PURPOSE" ]]; then
  PURPOSE="$(basename "$PROJECT_DIR") session"
fi

# Check dependencies
check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: '$1' not found. Install it first."
    echo "  Claude Code:  npm install -g @anthropic-ai/claude-code"
    echo "  Gemini CLI:   npm install -g @google/gemini-cli"
    echo "  Codex CLI:    npm install -g @openai/codex"
    exit 1
  fi
}

check_dep tmux
check_dep claude

if [[ "$SUB_AGENT" == "codex" ]]; then
  check_dep codex
else
  check_dep gemini
fi

# If session already exists, just attach
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists. Attaching..."
  echo "(Use 'bash scripts/status.sh' to see all active sessions)"
  tmux attach-session -t "$SESSION"
  exit 0
fi

echo "Creating tmux session '$SESSION'..."
echo "  Sub-agent:   $SUB_AGENT (pane 0.0)"
echo "  Orchestrator: claude   (pane 0.1)"
echo "  Project dir: $PROJECT_DIR"
echo "  Purpose:     $PURPOSE"
echo ""

# Create session and split into two panes
tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR"
tmux split-window -h -t "$SESSION:0" -c "$PROJECT_DIR"
tmux select-layout -t "$SESSION:0" even-horizontal

# Capture stable pane IDs (these survive pane reordering, unlike positional 0.0/0.1)
AGENT_PANE=$(tmux list-panes -t "$SESSION:0" -F '#{pane_id}' | sed -n '1p')
CLAUDE_PANE=$(tmux list-panes -t "$SESSION:0" -F '#{pane_id}' | sed -n '2p')

# Label panes for clarity
tmux select-pane -t "$AGENT_PANE" -T "sub-agent ($SUB_AGENT)"
tmux select-pane -t "$CLAUDE_PANE" -T "orchestrator (claude)"

# Enable pane border titles
tmux set-option -w -t "$SESSION:0" pane-border-status top 2>/dev/null || true

# Start sub-agent in left pane
if [[ "$SUB_AGENT" == "codex" ]]; then
  tmux send-keys -t "$AGENT_PANE" "codex" Enter
else
  tmux send-keys -t "$AGENT_PANE" "gemini" Enter
fi

# Wait for agent shell to initialize, then verify it launched
sleep 2
AGENT_CMD=$(tmux display-message -p -t "$AGENT_PANE" '#{pane_current_command}' 2>/dev/null || echo "unknown")
if [[ "$AGENT_CMD" == "bash" || "$AGENT_CMD" == "zsh" || "$AGENT_CMD" == "sh" ]]; then
  echo "WARNING: $SUB_AGENT may not have started (pane is still running $AGENT_CMD)."
  echo "  After attaching, check the left pane and run: $SUB_AGENT"
  echo ""
else
  echo "  $SUB_AGENT started (pane $AGENT_PANE, process: $AGENT_CMD)"
fi

# Start Claude in right pane
tmux send-keys -t "$CLAUDE_PANE" "claude" Enter
sleep 2
CLAUDE_CMD=$(tmux display-message -p -t "$CLAUDE_PANE" '#{pane_current_command}' 2>/dev/null || echo "unknown")
if [[ "$CLAUDE_CMD" == "bash" || "$CLAUDE_CMD" == "zsh" || "$CLAUDE_CMD" == "sh" ]]; then
  echo "WARNING: Claude Code may not have started (pane is still running $CLAUDE_CMD)."
  echo "  After attaching, check the right pane and run: claude"
  echo ""
else
  echo "  Claude started  (pane $CLAUDE_PANE, process: $CLAUDE_CMD)"
fi

# Register session in the manifest
mkdir -p "$MANIFEST_DIR"
LAUNCHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

python3 - <<PYEOF
import json, os

manifest_file = "$MANIFEST_FILE"
entry = {
  "name": "$SESSION",
  "purpose": "$PURPOSE",
  "project_dir": "$PROJECT_DIR",
  "agents": ["$SUB_AGENT"],
  "launched_at": "$LAUNCHED_AT",
  "panes": {
    "$SUB_AGENT": "$AGENT_PANE",
    "claude": "$CLAUDE_PANE"
  }
}

if os.path.exists(manifest_file):
  with open(manifest_file) as f:
    data = json.load(f)
else:
  data = {"sessions": []}

# Replace any existing entry with the same session name
data["sessions"] = [s for s in data["sessions"] if s["name"] != "$SESSION"]
data["sessions"].append(entry)

with open(manifest_file, "w") as f:
  json.dump(data, f, indent=2)
PYEOF

echo ""
echo "Session registered. Use 'bash scripts/status.sh' to see all active sessions."
echo ""
echo "Tips:"
echo "  Switch panes:          Ctrl+b then arrow keys"
echo "  Detach (keep running): Ctrl+b then d"
echo "  Re-attach later:       tmux attach -t $SESSION"
echo "  Check all sessions:    bash scripts/status.sh"
echo "  Close when done:       bash scripts/teardown.sh"
echo ""
echo "Next steps:"
echo "  1. In Claude's pane (right), tell it what you want to build"
echo "  2. Claude will use /gsd:plan-phase to plan, then delegate to the sub-agent"
echo "  3. See QUICKSTART.md for a full walkthrough"
echo ""

# Focus the orchestrator pane and attach
tmux select-pane -t "$CLAUDE_PANE"
tmux attach-session -t "$SESSION"
