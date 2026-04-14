# Workspace Overview: [YOUR PROJECT NAME]

> **Setup instructions:** Replace every `[BRACKETED]` section below with your project's details.
> Ask Claude Code to fill this out for you: *"Read the codebase and fill out GEMINI.md."*

---

## What This Project Is

[2-3 sentences describing what the project does and what problem it solves.]

**Current goal:** [What you're working on right now — e.g., "v1.0 MVP", "Phase 3 — user auth"]

---

## Tech Stack

- **Backend:** [e.g., Python 3.11 / FastAPI]
- **Frontend:** [e.g., Next.js 14 / TypeScript / Tailwind]
- **Database:** [e.g., PostgreSQL 15]
- **AI/LLM:** [e.g., Gemini 2.0 Flash]
- **Tests:** [e.g., pytest / Jest]
- **Deploy:** [e.g., Docker / GCP Cloud Run]

---

## Project Layout

```
[Paste your project tree here — just the key directories, not node_modules]

Example:
my-project/
├── backend/
│   ├── app/
│   │   ├── main.py          # FastAPI entry point
│   │   ├── routers/         # Route handlers
│   │   └── services/        # Business logic
│   └── tests/
├── frontend/
│   ├── app/                 # Next.js App Router pages
│   └── components/
└── .planning/               # GSD plans and state
    ├── ROADMAP.md
    └── STATE.md
```

---

## Key Commands

```bash
# Start backend
[your backend start command]

# Run tests
[your test command]

# Lint
[your lint command]

# Build
[your build command]
```

---

## Code Conventions

[List your project's conventions. Examples:]
- Use `snake_case` for Python, `camelCase` for TypeScript
- All API endpoints require `X-API-Key` header
- Database queries go in `services/database.py`, not inline in routes
- Commit format: `type(scope): description` (e.g., `feat(auth): add login endpoint`)
- Never commit secrets or `.env` files

---

## Multi-Agent Protocol

**You are a sub-agent.** Claude Code is the orchestrator running in pane `orchestra:0.1`.
It sends you tasks via tmux and monitors your output. Follow these rules exactly.

### How you receive tasks

Claude types tasks directly into your terminal via `tmux send-keys`. When you see a task appear, treat it as a new prompt and start working.

### Completion signal — REQUIRED

After finishing every task (code written, tests passing, committed), output this exact line as your **final message**:

```
PHASE_COMPLETE: Phase N — <one-line summary of what was done>
```

Example:
```
PHASE_COMPLETE: Phase 3 — POST /users endpoint added, validation + tests, all passing
```

Then output:
```
AWAITING_INSTRUCTIONS
```

**This is how Claude knows you're done.** It polls your pane looking for `PHASE_COMPLETE`. If you don't output this, Claude will keep waiting.

### Notifying Claude directly (when asked)

If Claude explicitly asks you to ping it, run these two commands — the `-l` flag sends the message literally so brackets and colons in your output don't get misinterpreted as terminal escape sequences:

```bash
tmux send-keys -l -t orchestra:0.1 "AGENT_PING: [task] complete. Files changed: [list]. Issues: [any deviations or problems]. Tests: [pass/fail + counts]. — AWAITING_INSTRUCTIONS"
tmux send-keys -t orchestra:0.1 "" Enter
```

### Rules — read these carefully

1. **Never start the next task until Claude sends it.** After PHASE_COMPLETE, wait.
2. **Always use non-interactive flags.** `npm install --yes`, `apt install -y`, `npx --yes`. Never run a command that pauses for y/n — Claude can't respond to interactive sub-shells.
3. **Always commit before signaling PHASE_COMPLETE.** Uncommitted work doesn't count.
4. **Run `git status --short` after committing** to confirm a clean tree.
5. **One task at a time.** Don't batch multiple phases into one response.
6. **Don't start the backend server** (`uvicorn`, `gunicorn`, etc.) unless explicitly told to — it will block your terminal and you won't be able to run further commands.
7. **Read the plan file first.** When told to execute a phase, read `.planning/phases/N-slug/PLAN.md` before writing any code.

---

## Planning Files Location

All GSD plans live in `.planning/phases/`. When told to execute a phase, the plan will be at:

```
.planning/phases/N-phase-name/PLAN.md
```

Read the entire PLAN.md before starting. It contains the task list, file list, and verification steps.
