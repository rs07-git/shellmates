#!/usr/bin/env bash
# launch-full-team.sh — 4-pane multi-agent session
#
# Layout:
#   ┌──────────────┬──────────────┐
#   │  gemini-1    │   claude     │
#   │  (worker A)  │ (orchestrat) │
#   ├──────────────┼──────────────┤
#   │  gemini-2    │   codex      │
#   │  (worker B)  │  (executor)  │
#   └──────────────┴──────────────┘
#
# Pane targets:
#   full:0.0  — Gemini CLI worker A
#   full:0.1  — Claude Code orchestrator
#   full:0.2  — Gemini CLI worker B
#   full:0.3  — Codex CLI executor
#
# Usage:
#   ./scripts/launch-full-team.sh [--session name] [--dir path]

set -euo pipefail

SESSION="full"
PROJECT_DIR="${PWD}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --dir)     PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--session name] [--dir path]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists. Attaching..."
  tmux attach-session -t "$SESSION"
  exit 0
fi

echo "Creating 4-pane session '$SESSION'..."

# Create and tile into 4 panes
tmux new-session -d -s "$SESSION" -c "$PROJECT_DIR"          # pane 0
tmux split-window -h -t "$SESSION:0" -c "$PROJECT_DIR"       # pane 1 (right)
tmux split-window -v -t "$SESSION:0.0" -c "$PROJECT_DIR"     # pane 2 (bottom-left)
tmux split-window -v -t "$SESSION:0.1" -c "$PROJECT_DIR"     # pane 3 (bottom-right)

# Label panes
tmux select-pane -t "$SESSION:0.0" -T "gemini-A"
tmux select-pane -t "$SESSION:0.1" -T "orchestrator (claude)"
tmux select-pane -t "$SESSION:0.2" -T "gemini-B"
tmux select-pane -t "$SESSION:0.3" -T "codex"

# Start sub-agents
tmux send-keys -t "$SESSION:0.0" "gemini" Enter
tmux send-keys -t "$SESSION:0.2" "gemini" Enter
tmux send-keys -t "$SESSION:0.3" "codex" Enter

# Start orchestrator last
sleep 1
tmux send-keys -t "$SESSION:0.1" "claude" Enter

tmux select-pane -t "$SESSION:0.1"

echo ""
echo "4-pane session ready."
echo "  Pane 0.0 — Gemini worker A"
echo "  Pane 0.1 — Claude orchestrator"
echo "  Pane 0.2 — Gemini worker B"
echo "  Pane 0.3 — Codex executor"
echo ""

tmux attach-session -t "$SESSION"
