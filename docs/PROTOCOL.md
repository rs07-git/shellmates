# Protocol Reference

The full IPC spec between the Claude orchestrator and sub-agents.

---

## How Communication Works

All coordination happens through tmux terminal I/O. No sockets, no shared files, no APIs needed.

- **Claude sends tasks** by typing into sub-agent panes with `tmux send-keys`
- **Sub-agents report back** by printing signals to their own stdout
- **Claude reads output** by capturing sub-agent panes with `tmux capture-pane`
- **Sub-agents can actively notify Claude** by using `tmux send-keys` to type into Claude's pane

---

## Pane Targets

Default 2-pane layout (`launch.sh`):

| Target | Role |
|--------|------|
| `orchestra:0.0` | Sub-agent (Gemini or Codex) |
| `orchestra:0.1` | Orchestrator (Claude Code) |

Full 4-pane layout (`launch-full-team.sh`):

| Target | Role |
|--------|------|
| `full:0.0` | Gemini worker A |
| `full:0.1` | Orchestrator (Claude Code) |
| `full:0.2` | Gemini worker B |
| `full:0.3` | Codex executor |

---

## Sending a Task (Orchestrator → Sub-agent)

```bash
tmux send-keys -t orchestra:0.0 "Your task description here." Enter
```

The text is typed directly into the sub-agent's terminal as if a human typed it.

**For longer tasks, write to a temp file first:**

```bash
cat > /tmp/task.txt << 'EOF'
Execute Phase 3 — User Authentication.

Plan is at: .planning/phases/3-auth/PLAN.md — read it first.
Project context is in GEMINI.md.

After each logical step, commit your work.
When everything is done and tests pass, output:
PHASE_COMPLETE: Phase 3 — <one-line summary>
EOF

tmux send-keys -t orchestra:0.0 "$(cat /tmp/task.txt)" Enter
```

---

## Completion Signal (Sub-agent → stdout)

```
PHASE_COMPLETE: Phase N — <one-line summary>
```

Sub-agents output this as their final line when a task is done. Always followed by:

```
AWAITING_INSTRUCTIONS
```

---

## Reading Sub-agent Output (Orchestrator polls)

```bash
# Quick check — last 20 lines
tmux capture-pane -t orchestra:0.0 -p | tail -20

# Larger window
tmux capture-pane -t orchestra:0.0 -p -S -100 | tail -60

# Save to file for detailed review
tmux capture-pane -t orchestra:0.0 -p -S -200 > /tmp/agent-output.txt
cat /tmp/agent-output.txt
```

---

## Active Notification (Sub-agent → Orchestrator pane)

When Claude asks a sub-agent to actively notify it (not just wait to be polled), the sub-agent runs:

```bash
tmux send-keys -t orchestra:0.1 "AGENT_PING: Phase 3 complete. Files changed: api/auth.py, tests/test_auth.py. Issues: none. Tests: pytest 14/14 pass. — AWAITING_INSTRUCTIONS" Enter
```

This physically types the message into Claude's terminal. The sub-agent's own stdout alone is not visible to Claude unless Claude polls.

**When to use active ping vs. passive PHASE_COMPLETE:**
- `PHASE_COMPLETE` in stdout — always output this, every time
- `AGENT_PING` via send-keys — only when Claude explicitly requests active notification, or for urgent errors

---

## Checking Completion via Git

Git commits are more reliable than stdout signals. Always verify:

```bash
# New commits since last check
git log --oneline -5

# What changed
git diff HEAD~1 --stat
git diff HEAD~1
```

---

## Polling Loop Pattern

When Claude needs to wait for a signal:

```bash
# Poll every 15 seconds, up to 10 minutes
for i in $(seq 1 40); do
  OUTPUT=$(tmux capture-pane -t orchestra:0.0 -p | tail -5)
  if echo "$OUTPUT" | grep -q "PHASE_COMPLETE"; then
    echo "Done: $OUTPUT"
    break
  fi
  sleep 15
done
```

---

## Signals Reference

| Signal | Direction | How |
|--------|-----------|-----|
| `tmux send-keys -t pane "task" Enter` | Claude → Sub-agent | Delegates a task |
| `PHASE_COMPLETE: Phase N — summary` | Sub-agent stdout | Task complete |
| `AWAITING_INSTRUCTIONS` | Sub-agent stdout | Agent idle, ready |
| `AGENT_PING: ... AWAITING_INSTRUCTIONS` | Sub-agent → Claude pane | Active notification |
| `tmux capture-pane -t pane -p \| tail -N` | Claude reads pane | Checks sub-agent output |
