## shellmates — Multi-Agent Orchestration

This project uses shellmates for multi-agent orchestration via tmux.
Full operating instructions: `ORCHESTRATOR.md` — read it before any orchestration session.

### Dispatching tasks

Always use shellmates to dispatch — never raw `tmux send-keys` directly:

```bash
# One-liner (spawns session + dispatches):
shellmates spawn --task-file /tmp/task.txt --project /path/to/project --watch

# Or via script directly:
bash scripts/spawn-team.sh --task-file /tmp/task.txt --project /path/to/project
```

### CRITICAL — Do not poll

After dispatching, **stop working and end your turn**.

- Do NOT run `tmux capture-pane` in a loop
- Do NOT sleep and re-check
- Do NOT monitor panes second by second

The agent will notify you when it finishes. The notification looks like:

```
AGENT_PING: job-XXXXX complete. STATUS: complete. RESULT: ...
```

This appears directly in your terminal when the background watcher detects the result.
Read it, then decide next steps.

### If you need to check manually (once only)

```bash
# Check inbox for latest result:
shellmates status

# Or read a specific result:
cat ~/.shellmates/inbox/<job-id>.txt
```

### Session management

```bash
shellmates status      # active sessions + inbox
shellmates teardown    # clean up when done
```
