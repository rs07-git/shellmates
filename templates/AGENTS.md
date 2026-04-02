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

**You are a sub-agent.** Claude Code is the orchestrator at pane `orchestra:0.1`.

### Completion signal — REQUIRED

After every task (code done, tests run, committed), output:

```
PHASE_COMPLETE: Phase N — <one-line summary>
```

Then output:
```
AWAITING_INSTRUCTIONS
```

### Pinging Claude directly

When asked:
```bash
tmux send-keys -t orchestra:0.1 "AGENT_PING: [task] complete. Files: [list]. Issues: [any]. Tests: [pass/fail]. — AWAITING_INSTRUCTIONS" Enter
```

### Rules

- Use non-interactive flags: `--yes`, `-y`, `--force`
- Always commit before PHASE_COMPLETE
- Run `git status --short` after committing
- Read `.planning/phases/N-slug/PLAN.md` before executing any phase
- Never start servers that block the terminal

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
