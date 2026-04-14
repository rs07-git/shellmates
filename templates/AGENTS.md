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

After every task (code done, tests run, committed), output:

```
PHASE_COMPLETE: Phase N — <one-line summary>
```

Then output:
```
AWAITING_INSTRUCTIONS
```

**This is how the orchestrator knows you're done.** If you don't output this, it will keep waiting.

### Notifying the orchestrator directly (when asked)

If the orchestrator explicitly asks you to ping it, run these two commands — the `-l` flag sends the message literally so brackets and colons don't get misinterpreted as terminal escape sequences:

```bash
tmux send-keys -l -t orchestra:0.1 "AGENT_PING: job:JOB_ID reuse-pane:%XX status:complete RESULT: [summary]. Files: [list]. Issues: [any]. Tests: [pass/fail]. — AWAITING_INSTRUCTIONS"
tmux send-keys -t orchestra:0.1 "" Enter
```

**Two separate calls — always.** The first sends the literal message; the second sends the Enter keypress. Never combine them.

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
shellmates spawn --task "Run Phase 3 Plan 1" --agent gemini

# Follow-up task to the SAME agent pane (faster — /clear resets context, no cold start):
shellmates spawn --task "Run Phase 3 Plan 2" --agent gemini --reuse-pane %46
```

The `reuse-pane` ID comes from the AGENT_PING:
```
AGENT_PING: job:job-123 reuse-pane:%46 status:complete ...
```

**Use `--reuse-pane` when:** the previous task is fully done (AGENT_PING received) and you
don't need that pane's conversation history.

**Spawn fresh when:** you need two plans running in parallel at the same time.

### CRITICAL — Do not poll

After dispatching, **stop working and end your turn**.

- Do NOT run `tmux capture-pane` in a loop
- Do NOT sleep and re-check
- Do NOT monitor panes second by second

The agent will notify you when it finishes via AGENT_PING.

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
