## shellmates — Multi-Agent Orchestration

This project uses shellmates for multi-agent orchestration via tmux.
Full operating instructions: `ORCHESTRATOR.md` — read it before any orchestration session.

### At the start of EVERY response — drain pending pings first

Before doing anything else, run this one-liner. Pings are sometimes queued here when they
arrived while you had a permission dialog open:

```bash
for f in ~/.shellmates/pending-pings/*.txt; do [ -f "$f" ] || continue; cat "$f"; rm "$f"; done
```

If any AGENT_PING lines appear, treat them exactly as live pings — they just arrived late.

### Dispatching tasks

Always use shellmates to dispatch — never raw `tmux send-keys` directly:

```bash
# First task to an agent (spawns a new pane):
shellmates spawn --task "Run Phase 3 Plan 1" --agent gemini

# Follow-up task to the SAME agent pane (faster — /clear resets context, no cold start):
shellmates spawn --task "Run Phase 3 Plan 2" --agent gemini --reuse-pane %46
```

The `reuse-pane` ID comes from the AGENT_PING:
```
AGENT_PING: job:job-123 reuse-pane:%46 status:complete ...
```

**Use `--reuse-pane` when:** the previous task is fully done (AGENT_PING received) and you
don't need that pane's conversation history (GSD phases write everything to files — you
almost never need the history).

**Spawn fresh when:** you need two plans running in parallel at the same time.

### CRITICAL — Do not poll

After dispatching, **stop working and end your turn**.

- Do NOT run `tmux capture-pane` in a loop
- Do NOT sleep and re-check
- Do NOT monitor panes second by second

The agent will notify you when it finishes. The notification looks like:

```
AGENT_PING: job:job-XXXXX reuse-pane:%46 status:complete idle-panes:%48,%49 busy-panes:%50 free-slots:2 RESULT: Plan 2 done ... — AWAITING_INSTRUCTIONS
```

Read it, then dispatch the next plan (using `--reuse-pane %46` if sequential, or a fresh
spawn if parallel).

### Pane hygiene — read the inventory fields

Every AGENT_PING includes a live snapshot of your session's pane state:

| Field | Meaning |
|-------|---------|
| `idle-panes:%15,%18` | Agent CLIs sitting at a prompt — ready for reuse or safe to kill |
| `busy-panes:%16` | Agent CLIs still running a task — do not kill or send to these |
| `free-slots:3` | How many new panes you can still open (cap is 6) |

**What to do with this information:**

- **Reuse idle panes** for the next sequential task (`--reuse-pane %ID`) instead of spawning fresh
- **Spawn in parallel** when `free-slots > 0` and the next tasks are independent — don't wait for one agent to finish before starting another
- **Kill idle panes you're done with** — once a pane's agent has finished its last task and you have no more work for it, kill it:
  ```bash
  tmux kill-pane -t %48
  ```
- **Never let idle panes accumulate.** Each costs tmux resources and makes the session harder to read.

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
