# AGENTS.md

This file provides guidance to AI coding agents (Codex, Warp, Gemini CLI, etc.) operating in this repository.

> **Setup:** Replace `[BRACKETED]` sections with your project details.
> Ask Claude: *"Read the codebase and fill out AGENTS.md."*

---

## Project Overview

[2-3 sentences on what this project does.]

**Stack:** [e.g., Python/FastAPI + Next.js + PostgreSQL]
**Current milestone:** [e.g., v1.0 — MVP]

---

## Build & Run Commands

```bash
# Backend
[start command]

# Frontend
[start command]

# Tests
[test command]

# Lint
[lint command]
```

---

## Key Files

```
[List your most important files]

Example:
backend/app/main.py        — FastAPI entry point
backend/app/services/      — Business logic
frontend/app/              — Next.js pages
.planning/STATE.md         — Current project state
.planning/ROADMAP.md       — Phase roadmap
```

---

## Multi-Agent Protocol

**You are a sub-agent.** The orchestrator dispatches tasks to you via tmux and monitors your output. Follow these rules exactly.

### How you receive tasks

The orchestrator types tasks directly into your terminal via `tmux send-keys`. When you see a task appear, treat it as a new prompt and start working.

### Completion signal — REQUIRED

After every task (code done, tests run, committed), do these **in order**:

**1. Write your result to the inbox file** (the exact path and format are in the task footer):
```bash
mkdir -p ~/.shellmates/inbox && cat > ~/.shellmates/inbox/<JOB_ID>.txt << 'EOF'
AGENT: codex
JOB: <JOB_ID>
STATUS: complete
CHANGED: <comma-separated file paths, or none>
RESULT: <≤5 line summary of what was done>
EOF
```

**2. Output the completion signal:**
```
PHASE_COMPLETE: Phase N — <one-line summary>
```

Then output:
```
AWAITING_INSTRUCTIONS
```

**Writing the inbox file is what notifies the orchestrator.** A background watcher detects the file and delivers an AGENT_PING automatically. `PHASE_COMPLETE` is for terminal visibility only — if you skip the inbox write, the orchestrator will never know you finished.

### Direct ping (emergency only)

In normal flow you don't need to do this — writing the inbox file is sufficient. If the orchestrator has explicitly provided its pane address and asked for a manual ping, use the `-l` flag so brackets and colons aren't misinterpreted as terminal escape sequences:

```bash
tmux send-keys -l -t <PANE_ID> "AGENT_PING: job:JOB_ID reuse-pane:%XX status:complete RESULT: [summary]. Files: [list]. Issues: [any]. Tests: [pass/fail]. — AWAITING_INSTRUCTIONS"
tmux send-keys -t <PANE_ID> "" Enter
```

**Two separate calls — always.** Replace `<PANE_ID>` with the address from your task instructions. **Never guess the pane address** — it is not universally `orchestra:0.1`; it depends on how shellmates was started.

### Rules

1. **Never start the next task until the orchestrator sends it.** After PHASE_COMPLETE, wait.
2. **Use non-interactive flags:** `--yes`, `-y`, `--force`, `npx --yes`. Never run a command that pauses for y/n.
3. **Always commit before PHASE_COMPLETE.** Uncommitted work doesn't count.
4. **Run `git status --short` after committing** to confirm a clean tree.
5. **One task at a time.** Don't batch multiple phases into one response.
6. **Never start servers that block the terminal** (`uvicorn`, `gunicorn`, etc.) unless explicitly told to.
7. **Read the plan file first.** When told to execute a phase, read `.planning/phases/N-slug/PLAN.md` before writing any code.

---

## If you are the orchestrator

When acting as the orchestrator (dispatching tasks rather than executing them), follow these additional rules.

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
shellmates spawn --task "Run Phase 3 Plan 1" --agent gemini   # or --agent claude / --agent codex

# Follow-up task to the SAME agent pane (faster — /clear resets context, no cold start):
shellmates spawn --task "Run Phase 3 Plan 2" --agent gemini --reuse-pane %46
```

The `reuse-pane` ID comes from the AGENT_PING:
```
AGENT_PING: job:job-123 reuse-pane:%46 status:complete ...
```

**Use `--reuse-pane` when:** the previous task is fully done (AGENT_PING received) and you
don't need that pane's conversation history. Shellmates sends `/clear` to reset the agent's
context — no cold start needed.

**Spawn fresh when:** you need two plans running in parallel at the same time.

### CRITICAL — Do not poll

After dispatching, **stop working and end your turn**.

- Do NOT run `tmux capture-pane` in a loop
- Do NOT sleep and re-check
- Do NOT monitor panes second by second

The agent will notify you when it finishes via AGENT_PING:

```
AGENT_PING: job:job-XXXXX reuse-pane:%46 status:complete idle-panes:%48 busy-panes:%50 free-slots:2 RESULT: ... — AWAITING_INSTRUCTIONS
```

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
shellmates status
cat ~/.shellmates/inbox/<job-id>.txt
```

---

## Code Conventions

[Your conventions here]

---

## Codex Multi-Agent Roles

This project includes `.codex/config.toml` with the following specialized roles:

| Role | Use for |
|------|---------|
| `planner` | Producing PLAN.md from a task description |
| `researcher` | Discovering constraints before planning |
| `executor` | Implementing an approved plan |
| `verifier` | Independent testing and UAT verification |
| `reviewer` | Code review for regressions and security |
| `explorer` | Read-only codebase mapping |

To invoke a role pattern:
```
Run a [researcher] + [planner] + [executor] workflow for:
[task description]
```
