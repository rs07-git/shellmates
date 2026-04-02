# shellmates — Agent Setup Instructions

> **You are an AI agent.** The user wants to set up the shellmates multi-agent workflow
> for their project. This file is your complete brief. Execute all steps autonomously.
> Ask the user only the questions marked **[ASK]**. Everything else, detect or decide yourself.

---

## What you're setting up

shellmates lets Claude Code (orchestrator) delegate work to Gemini CLI and/or Codex CLI
via tmux pane messaging. Claude plans with GSD, sends tasks to sub-agents with
`tmux send-keys`, and monitors completion via `tmux capture-pane`.

Three files make it work:
- **CLAUDE.md** — Claude reads this automatically on startup. You'll add a shellmates section.
- **GEMINI.md** — Gemini CLI reads this automatically on startup. You'll create or update this.
- **ORCHESTRATOR.md** — Claude's full operating instructions. You'll copy this in.

---

## Step 1 — Ask the user two questions

Before doing anything, ask:

1. **[ASK]** "Which sub-agent(s) do you want to use — Gemini, Codex, or both?"
   (Default: Gemini)

2. **[ASK]** "What should the tmux session be named?"
   (Default: `orchestra`. If they say their project name or anything else, use that.)

Store these as `SUB_AGENT` and `SESSION_NAME`. Use them throughout the rest of setup.

---

## Step 2 — Detect the environment

Check all of the following and make a note of what's missing:

```bash
# OS
uname -s    # Darwin = macOS, Linux = Linux

# Tools
command -v tmux    # is tmux installed?
command -v claude  # is Claude Code installed?
command -v gemini  # is Gemini CLI installed?
command -v codex   # is Codex CLI installed?

# API keys
echo $ANTHROPIC_API_KEY
echo $GEMINI_API_KEY   # also check $GOOGLE_API_KEY
echo $OPENAI_API_KEY

# Project files
ls CLAUDE.md 2>/dev/null
ls GEMINI.md 2>/dev/null
ls AGENTS.md 2>/dev/null
ls .planning/STATE.md 2>/dev/null

# Project type (for filling in GEMINI.md later)
ls package.json pyproject.toml requirements.txt Cargo.toml go.mod 2>/dev/null
```

---

## Step 3 — Install missing tools

### tmux (required)

```bash
# macOS
brew install tmux

# Linux (Debian/Ubuntu)
sudo apt install -y tmux

# Linux (Fedora/RHEL)
sudo dnf install -y tmux
```

### Claude Code (required — this is the orchestrator)

```bash
npm install -g @anthropic-ai/claude-code
```

### Gemini CLI (if SUB_AGENT includes Gemini)

```bash
npm install -g @google/gemini-cli
```

### Codex CLI (if SUB_AGENT includes Codex)

```bash
npm install -g @openai/codex
```

### GSD — the planning framework

```bash
npx get-shit-done-cc@latest
```

After installing, tell the user to restart Claude Code so GSD commands become available.

### API keys

If any API keys are missing, tell the user which ones to set and where to add them:

```bash
# Add to ~/.zshrc or ~/.bashrc:
export ANTHROPIC_API_KEY="..."
export GEMINI_API_KEY="..."      # for Gemini CLI
export OPENAI_API_KEY="..."      # for Codex CLI
```

Then: `source ~/.zshrc`

---

## Step 4 — Copy ORCHESTRATOR.md into the project

Copy `ORCHESTRATOR.md` from the shellmates repo into the user's project root.
Then open it and replace every instance of `orchestra` with `SESSION_NAME`
and every instance of `orchestra:0.0` with `SESSION_NAME:0.0`, etc.

If the user is using Codex instead of Gemini, update the sub-agent description accordingly.

---

## Step 5 — Update CLAUDE.md

Claude Code reads `CLAUDE.md` automatically on startup. You need to add a shellmates
section to it so Claude knows about the orchestration workflow without being told each session.

**If CLAUDE.md already exists:** append the following block to the bottom.
**If CLAUDE.md doesn't exist:** create it with just this block.

```markdown
## shellmates — Multi-Agent Orchestration

This project uses shellmates for multi-agent orchestration via tmux.
Full operating instructions are in ORCHESTRATOR.md — read it at session start.

Setup:
- tmux session: SESSION_NAME
- Sub-agent pane: SESSION_NAME:0.0  ([GEMINI/CODEX] CLI — executor)
- Orchestrator pane: SESSION_NAME:0.1 (Claude Code — you)

Quick reference:
- Plan work:        /gsd:plan-phase N
- Delegate task:    tmux send-keys -t SESSION_NAME:0.0 "task..." Enter
- Check completion: tmux capture-pane -t SESSION_NAME:0.0 -p | tail -20
- Read agent output: tmux capture-pane -t SESSION_NAME:0.0 -p -S -100 | tail -60
- Check git:        git log --oneline -5

At the start of every orchestration session, read ORCHESTRATOR.md for the full protocol.
```

Replace `SESSION_NAME` and `[GEMINI/CODEX]` with the actual values from Step 1.

---

## Step 6 — Create or update GEMINI.md

Gemini CLI reads `GEMINI.md` automatically from the working directory on startup.
This is Gemini's entire understanding of the project — make it accurate and complete.

**If GEMINI.md doesn't exist:** create it from scratch using the template below.
**If GEMINI.md exists:** check if it has a "Multi-Agent Protocol" section.
  - If yes: verify the pane target (`orchestra:0.1`) matches `SESSION_NAME:0.1` and update if needed.
  - If no: append the Multi-Agent Protocol section from the template below.

To fill in the project details accurately, read the project's actual files:
- `package.json`, `pyproject.toml`, or `requirements.txt` → tech stack
- `README.md` → project description
- Directory structure → key file locations
- Existing `CLAUDE.md` → conventions and rules

**GEMINI.md template:**

```markdown
# Workspace Overview: [PROJECT NAME]

## What This Project Is

[2-3 sentences describing what the project does — fill this in from README.md or project context]

**Current goal:** [Current milestone or what's being worked on]

## Tech Stack

[Fill in from package.json / pyproject.toml / detected files]

## Project Layout

[Fill in with actual project tree — key directories only]

## Key Commands

```bash
# Tests
[detected test command]

# Lint  
[detected lint command]

# Build / run
[detected start command]
```

## Code Conventions

[Fill in from existing CLAUDE.md if it exists, or leave placeholder]
- Commit format: [detected or placeholder]
- Never commit .env files or secrets

## Multi-Agent Protocol

**You are a sub-agent.** Claude Code is the orchestrator at pane `SESSION_NAME:0.1`.
It sends you tasks via tmux and monitors your output. Follow these rules exactly.

### Completion signal — REQUIRED

After finishing every task (code written, tests passing, committed), output:

```
PHASE_COMPLETE: Phase N — <one-line summary>
```

Then output:
```
AWAITING_INSTRUCTIONS
```

This is how Claude knows you're done. It polls your pane for this signal.

### Pinging Claude directly (when asked)

```bash
tmux send-keys -t SESSION_NAME:0.1 "AGENT_PING: [task] complete. Files: [list]. Issues: [any]. Tests: [pass/fail]. — AWAITING_INSTRUCTIONS" Enter
```

### Rules

1. Never start the next task until Claude sends it
2. Use non-interactive flags: `--yes`, `-y`, `--force`
3. Always commit before PHASE_COMPLETE
4. Run `git status --short` after committing
5. Read `.planning/phases/N-slug/PLAN.md` before executing any phase
6. Never start servers that block the terminal (uvicorn, npm run dev, etc.)

## Planning Files

GSD plans live at `.planning/phases/N-phase-name/PLAN.md`. Always read the full plan before starting.
```

Replace `SESSION_NAME` with the actual session name from Step 1.

---

## Step 7 — Set up Codex config (if using Codex)

If SUB_AGENT includes Codex, copy the `.codex/` directory from the shellmates repo
into the user's project root. Then update `AGENTS.md` using the same template process
as GEMINI.md above (same project details, same protocol section, same session name).

---

## Step 8 — Initialize GSD (if needed)

Check if `.planning/STATE.md` exists.

**If it doesn't exist:**

Tell the user:
> "GSD isn't initialized for this project yet. Once you're in Claude Code,
> run `/gsd:new-project` (new project) or `/gsd:map-codebase` then `/gsd:new-project`
> (existing codebase). This creates the planning structure shellmates uses."

**If it exists:** No action needed.

---

## Step 9 — Generate SHELLMATES_WELCOME.md

Create a file called `SHELLMATES_WELCOME.md` in the project root.
This is the user's personalized tutorial — make it specific to their actual project,
not generic. Use everything you detected in Steps 2 and 6 to fill it in.

```markdown
# Welcome to shellmates!

Setup is complete. Here's everything you need to know to run your first session.

## What was configured

[List the exact changes made:]
- CLAUDE.md — [appended / created] with shellmates orchestration section
- GEMINI.md — [created / updated] with project context and sub-agent protocol
- ORCHESTRATOR.md — copied into project root
- Tools installed: [list what was actually installed]
- GSD: [installed / already present / needs initialization — tell them which]

## Your session layout

tmux session: **SESSION_NAME**

```
┌──────────────────────────────┬──────────────────────────────┐
│  [GEMINI/CODEX]  (pane 0.0)  │  Claude Code  (pane 0.1)     │
│  executor                    │  orchestrator (you)          │
└──────────────────────────────┴──────────────────────────────┘
```

## Start a session

```bash
bash /path/to/shellmates/scripts/launch.sh
```

Or manually:
```bash
tmux new-session -d -s SESSION_NAME -c /path/to/your/project
tmux split-window -h -t SESSION_NAME
tmux send-keys -t SESSION_NAME:0.0 "[gemini/codex]" Enter
tmux send-keys -t SESSION_NAME:0.1 "claude" Enter
tmux attach -t SESSION_NAME
```

## Scrolling in tmux — fix this before your first session

By default, tmux intercepts scroll events and cycles through shell history instead of scrolling the pane. Fix it once:

```bash
echo "set -g mouse on" >> ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

After this, you can scroll any pane with your mouse normally.

**Keyboard alternative:** `Ctrl+b [` to enter scroll mode → arrow keys / PgUp / PgDn → `q` to exit.

## Your first workflow

Once in the session, click into the **right pane (Claude)** and say:

> "I want to [fill in with something relevant to their actual project — e.g.,
> 'add user authentication' for a web app, 'add a new CLI command' for a CLI tool].
> Please use /gsd:plan-phase to plan it, then delegate to [Gemini/Codex] in pane SESSION_NAME:0.0."

## What happens

1. Claude runs `/gsd:plan-phase` → produces `.planning/phases/N-feature/PLAN.md`
2. Claude sends the plan to [Gemini/Codex] → `tmux send-keys -t SESSION_NAME:0.0`
3. [Gemini/Codex] reads the plan, implements, runs tests, commits
4. [Gemini/Codex] outputs `PHASE_COMPLETE: Phase N — summary`
5. Claude reads the output, checks git, reports back to you

## Useful commands (run in Claude's pane)

```bash
# Check what your sub-agent is doing right now
tmux capture-pane -t SESSION_NAME:0.0 -p | tail -20

# Check git for completed work
git log --oneline -5

# Check project status
/gsd:progress
```

## Where to go from here

- `ORCHESTRATOR.md` — Claude's full operating instructions
- `GEMINI.md` — Sub-agent's project context (keep this updated as your project evolves)
- `docs/WORKFLOW.md` — Deep dive on the plan/execute split
- `docs/PROTOCOL.md` — Full tmux IPC reference
- `examples/end-to-end.md` — Complete walkthrough of a real feature

---

*Generated by shellmates setup. You can delete this file once you're comfortable with the workflow.*
```

---

## Step 10 — Tell the user what to do right now

Once all steps are complete, give the user a clear 3-step summary:

```
Setup complete. Here's what to do right now:

1. [If GSD not initialized]: Run /gsd:new-project inside Claude Code to set up the planning structure.
   [If GSD already set up]: You're ready to go.

2. Start your first shellmates session:
   bash /path/to/shellmates/scripts/launch.sh

3. In Claude's pane (right side), read SHELLMATES_WELCOME.md for your personalized tutorial:
   "Read SHELLMATES_WELCOME.md"

That's it.
```

---

## Notes for the setup agent

- **Be surgical with CLAUDE.md.** If it exists and already has content, append — don't replace.
- **Fill in GEMINI.md with real project details.** Read the actual codebase. Generic placeholders are worse than nothing — Gemini will hallucinate if GEMINI.md doesn't match reality.
- **The session name matters.** Every hardcoded `orchestra:0.0` in every file must match SESSION_NAME. Find and replace all of them.
- **If something can't be automated** (e.g., user needs to set an API key manually), say so clearly and tell them exactly what command to run.
- **Don't over-ask.** You asked two questions in Step 1. Don't ask more unless something is genuinely ambiguous.
