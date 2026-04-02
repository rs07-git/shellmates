#!/usr/bin/env bash
# launch.sh — Start or restore the tmux-ai-orchestra session
#
# Usage:
#   ./scripts/launch.sh                    # 2-pane: Gemini + Claude
#   ./scripts/launch.sh --codex            # 2-pane: Codex + Claude
#   ./scripts/launch.sh --session myname   # Custom session name (default: orchestra)
#
# Pane layout:
#   0.0  — Sub-agent (Gemini CLI or Codex CLI)
#   0.1  — Orchestrator (Claude Code)

set -euo pipefail

SESSION="orchestra"
SUB_AGENT="gemini"   # "gemini" or "codex"
PROJECT_DIR="${PWD}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex)     SUB_AGENT="codex"; shift ;;
    --session)   SESSION="$2"; shift 2 ;;
    --dir)       PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--codex] [--session name] [--dir path]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

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
  tmux attach-session -t "$SESSION"
  exit 0
fi

echo "Creating tmux session '$SESSION'..."
echo "  Sub-agent pane (0.0): $SUB_AGENT"
echo "  Orchestrator pane (0.1): claude"
echo "  Project dir: $PROJECT_DIR"
echo ""

# Create session with first window, split into two panes (left + right)
tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR"
tmux split-window -h -t "$SESSION:0" -c "$PROJECT_DIR"

# Pane 0 (left) = sub-agent
# Pane 1 (right) = claude orchestrator

# Size panes: 50/50 by default
tmux select-layout -t "$SESSION:0" even-horizontal

# Label panes for clarity
tmux select-pane -t "$SESSION:0.0" -T "sub-agent ($SUB_AGENT)"
tmux select-pane -t "$SESSION:0.1" -T "orchestrator (claude)"

# Start sub-agent in left pane
if [[ "$SUB_AGENT" == "codex" ]]; then
  tmux send-keys -t "$SESSION:0.0" "codex" Enter
else
  tmux send-keys -t "$SESSION:0.0" "gemini" Enter
fi

# Give sub-agent a moment to start, then launch Claude in right pane
sleep 1
tmux send-keys -t "$SESSION:0.1" "claude" Enter

# Focus the orchestrator pane
tmux select-pane -t "$SESSION:0.1"

echo ""
echo "Session ready. Attaching..."
echo ""
echo "Tips:"
echo "  Switch panes:        Ctrl+b then arrow keys"
echo "  Detach (keep running): Ctrl+b then d"
echo "  Re-attach later:     tmux attach -t $SESSION"
echo "  Kill session:        tmux kill-session -t $SESSION"
echo ""
echo "Next steps:"
echo "  1. In Claude's pane (right), tell it what you want to build"
echo "  2. Claude will use /gsd:plan-phase to plan, then delegate to the sub-agent"
echo "  3. See QUICKSTART.md for a full walkthrough"
echo ""

tmux attach-session -t "$SESSION"
