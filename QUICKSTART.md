# Quickstart

> **Fastest path:** paste this into your AI agent and skip this guide entirely:
> ```
> Read https://raw.githubusercontent.com/rs07-git/shellmates/main/INIT.md and set up shellmates for this project.
> ```
> Your agent will do all of this automatically.

---

This guide is for people who want to understand what's happening and do it themselves.

---

## Step 1 — Install the tools

You need four things. Open a terminal and run:

```bash
# 1. tmux (the session manager that connects the agents)
brew install tmux          # macOS
# sudo apt install tmux    # Linux

# 2. Claude Code (the orchestrator)
npm install -g @anthropic-ai/claude-code

# 3. Gemini CLI (the executor — or use Codex below)
npm install -g @google/gemini-cli

# 4. GSD — the planning framework that makes Claude's plans structured and executable
npx get-shit-done-cc@latest
```

**API keys** — you'll need these set in your shell:

```bash
export ANTHROPIC_API_KEY="your-key-here"
export GEMINI_API_KEY="your-key-here"   # or GOOGLE_API_KEY
```

Add these to your `~/.zshrc` or `~/.bashrc` so they're always available.

**Prefer Codex over Gemini?**
```bash
npm install -g @openai/codex
export OPENAI_API_KEY="your-key-here"
```

---

## Step 2 — Set up your project

Go to your project directory and copy in the instruction files:

```bash
cd /path/to/your/project

# Copy the orchestrator instructions (tells Claude how to run the workflow)
cp /path/to/shellmates/ORCHESTRATOR.md ./ORCHESTRATOR.md

# Copy the sub-agent instructions (tells Gemini how to behave and signal back)
cp /path/to/shellmates/templates/GEMINI.md ./GEMINI.md

# If using Codex instead of (or alongside) Gemini:
cp /path/to/shellmates/templates/AGENTS.md ./AGENTS.md
cp -r /path/to/shellmates/templates/.codex ./.codex
```

Now **edit `GEMINI.md`** and fill in your project details — the tech stack, key files, and any conventions Gemini needs to know. This is Gemini's only source of project context when it starts fresh.

> **Tip:** Ask Claude Code to fill out GEMINI.md for you: *"Read my codebase and fill out GEMINI.md based on what you find."*

---

## Step 3 — Initialize GSD for your project

GSD needs a planning directory to store plans, state, and roadmaps.

If you're starting a **new project**:
```bash
# Inside Claude Code, run:
/gsd:new-project
```
This walks you through requirements and creates a roadmap with phases.

If you have an **existing codebase**:
```bash
# Map the codebase first, then initialize
/gsd:map-codebase
/gsd:new-project
```

After this you'll have a `.planning/` directory with `ROADMAP.md`, `STATE.md`, and `REQUIREMENTS.md`.

> **Skip GSD for now?** That's fine — you can use this workflow without GSD. Claude will just plan manually instead of using `/gsd:plan-phase`. See `docs/WORKFLOW.md` for the no-GSD path.

---

## Step 4 — Launch the session

From your project directory:

```bash
bash /path/to/shellmates/scripts/launch.sh
```

This creates a tmux session called `orchestra` with two side-by-side panes and starts Gemini CLI on the left and Claude Code on the right.

**What you'll see:**
```
┌─────────────────────────┬─────────────────────────┐
│  $ gemini               │  $ claude               │
│                         │                         │
│  > Hello! How can I...  │  > Hello! How can I...  │
└─────────────────────────┴─────────────────────────┘
```

**tmux basics:**
- Switch panes: `Ctrl+b` then arrow keys
- Detach (leave running): `Ctrl+b` then `d`
- Re-attach later: `tmux attach -t orchestra`
- Kill session: `tmux kill-session -t orchestra`

**Scrolling — fix this first or you'll go crazy:**

By default, tmux intercepts scroll events and cycles through your shell history instead of scrolling the pane output. Fix it once:

```bash
# Add to ~/.tmux.conf (create the file if it doesn't exist):
echo "set -g mouse on" >> ~/.tmux.conf

# Apply without restarting:
tmux source-file ~/.tmux.conf
```

With mouse mode on, you can scroll any pane normally. Click a pane to focus it, then scroll.

**Keyboard scroll (no mouse / prefer keyboard):**
1. `Ctrl+b [` — enter copy/scroll mode
2. Arrow keys, `PgUp` / `PgDn`, or `Ctrl+u` / `Ctrl+d` to scroll
3. `q` — exit copy mode and return to normal

> **Why this matters:** when Gemini is executing a long task, you'll want to scroll back through its output to see what it did. Without mouse mode, you'll accidentally send keystrokes to the shell instead of scrolling.

---

## Step 5 — Run your first orchestrated workflow

Click into the **right pane (Claude)** and tell it what you want to build.

### Example prompt to Claude:

```
I want to add user authentication to this app.

Please:
1. Use /gsd:plan-phase to create a plan for this feature
2. Once the plan is ready, delegate it to Gemini in pane orchestra:0.0
3. Wait for Gemini to signal PHASE_COMPLETE
4. Report back what was done and whether I should review anything

The ORCHESTRATOR.md file in this project has your operating instructions.
```

### What happens next:

1. **Claude runs `/gsd:plan-phase`** — produces a structured `PLAN.md` in `.planning/phases/`
2. **Claude sends the plan to Gemini** via `tmux send-keys -t orchestra:0.0`
3. **Gemini reads the plan**, implements the feature, runs tests, commits
4. **Gemini outputs `PHASE_COMPLETE:`** — Claude detects this via `tmux capture-pane`
5. **Claude reviews** the git log and output, reports to you

---

---

## When you're done

Sessions persist in tmux until explicitly closed. A stale session from last week can confuse your next Claude orchestration — especially if it finds a `shellmates` session already open and tries to use it.

**Check what's running:**
```bash
bash /path/to/shellmates/scripts/status.sh
```

Output:
```
Shellmates sessions:

  #  name          purpose                       project                  agents  age    status
  ─────────────────────────────────────────────────────────────────────────────────────────────
  1  shellmates    haiku-duel demo               ~/Desktop/shellmates     gemini  6d     gemini idle, claude idle
  2  carebuddy     phase-182 production fixes    ~/Projects               codex   2h     codex active (node)
```

**Close sessions you're done with:**
```bash
bash /path/to/shellmates/scripts/teardown.sh
```

It shows you each session with its purpose and project, then asks which to close. You pick — nothing is killed automatically. This handles the case where you're running multiple shellmates sessions in parallel for different projects.

---

## What to do next

- Run the monitor in the background so you get live logs:
  ```bash
  bash /path/to/shellmates/scripts/monitor.sh > /tmp/orchestra.log 2>&1 &
  tail -f /tmp/orchestra.log
  ```

- Read `docs/WORKFLOW.md` to understand *why* the planning/execution split works
- Read `docs/PROTOCOL.md` for the full tmux IPC reference
- Check `examples/` for parallel agent patterns and more complex workflows

---

## Troubleshooting

**Gemini didn't respond to the task Claude sent**
→ Check that Gemini is running in pane `orchestra:0.0`: `tmux capture-pane -t orchestra:0.0 -p | tail -10`

**PHASE_COMPLETE never appeared**
→ GEMINI.md must be in your project root. Gemini reads it on startup. If you added it after starting, restart Gemini: `tmux send-keys -t orchestra:0.0 "/exit" Enter` then `tmux send-keys -t orchestra:0.0 "gemini" Enter`

**GSD commands not found**
→ Run `npx get-shit-done-cc@latest` and restart Claude Code

**More issues** → see `docs/TROUBLESHOOTING.md`
