# Troubleshooting

## GSD

### `/gsd:plan-phase` command not found

GSD isn't installed or Claude Code needs a restart.

```bash
# Install / update GSD
npx get-shit-done-cc@latest

# Then restart Claude Code (close and reopen the pane)
```

### GSD has no project to plan for

You need to initialize first:

```bash
/gsd:new-project      # new projects
/gsd:map-codebase     # existing codebases (run this first, then /gsd:new-project)
```

### `/gsd:progress` says state is stale

STATE.md exists but is out of date. Tell Claude: *"Read the current codebase state and update STATE.md to reflect what's actually been built."*

---

## tmux

### `tmux send-keys` typed text in the wrong place

The pane target doesn't exist or session name is wrong.

```bash
# List all panes
tmux list-panes -a

# Confirm your session name
tmux list-sessions
```

Update the pane target in ORCHESTRATOR.md and GEMINI.md to match.

### Session doesn't exist anymore

It was killed or the machine restarted. Re-launch:

```bash
cd /path/to/your/project
bash /path/to/shellmates/scripts/launch.sh
```

### Can't detach from session

Press `Ctrl+b` then `d`. Not `Ctrl+d` (that closes the pane).

---

## Sub-agent didn't respond to the task

**Check if the agent is running:**
```bash
tmux capture-pane -t orchestra:0.0 -p | tail -10
```

If you see a plain shell prompt (`$`) instead of the AI tool prompt, the agent exited.

**Restart it:**
```bash
tmux send-keys -t orchestra:0.0 "gemini" Enter
# or
tmux send-keys -t orchestra:0.0 "codex" Enter
```

**Then resend the task.**

---

## PHASE_COMPLETE never appeared

**Most likely cause:** GEMINI.md isn't in the project root, or Gemini started before GEMINI.md was added.

**Fix:**
1. Confirm GEMINI.md exists: `ls -la GEMINI.md`
2. Restart Gemini: `tmux send-keys -t orchestra:0.0 "/exit" Enter` then `tmux send-keys -t orchestra:0.0 "gemini" Enter`
3. Resend the task

**Other cause:** Gemini finished but formatted the signal differently. Check what it actually output:

```bash
tmux capture-pane -t orchestra:0.0 -p -S -50 | tail -30
```

Also check git — if commits were made, Gemini probably finished:

```bash
git log --oneline -5
```

---

## Gemini ran the wrong thing or went off-plan

Gemini's GEMINI.md or PLAN.md had ambiguous instructions. 

**Immediate fix:**
```bash
tmux send-keys -t orchestra:0.0 "Stop. The previous work was incorrect. [Describe what's wrong]. Please revert those changes with git reset and then [correct instruction]." Enter
```

**Prevention:**
- Make GEMINI.md very explicit about conventions and what NOT to do
- Make the PLAN.md task list specific and concrete
- Include test commands in the plan so Gemini can self-verify

---

## Two agents committed conflicting changes

They touched the same files in parallel.

**Fix:**
```bash
git log --oneline -10    # see what each committed
git diff HEAD~2          # see the conflict
```

Resolve manually in Claude's pane. Then tell the affected agent:
```bash
tmux send-keys -t orchestra:0.0 "There was a merge conflict. I've resolved it. The current state is: [describe]. Please continue from here." Enter
```

**Prevention:** Never assign overlapping files to parallel agents.

---

## Context got too long — agent lost track

Symptoms: agent contradicts earlier work, asks about things already done, ignores the plan.

**Fix:** Start a fresh agent session.

```bash
tmux send-keys -t orchestra:0.0 "/exit" Enter
sleep 2
tmux send-keys -t orchestra:0.0 "gemini" Enter
```

Then resend **only the current task** — not the entire conversation history. The PLAN.md and GEMINI.md give it everything it needs.

---

## API key errors

**Anthropic (Claude):**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
claude   # restart
```

**Google (Gemini):**
```bash
export GEMINI_API_KEY="AIza..."
# or
export GOOGLE_API_KEY="AIza..."
gemini   # restart
```

**OpenAI (Codex):**
```bash
export OPENAI_API_KEY="sk-..."
codex    # restart
```

Add these exports to your `~/.zshrc` or `~/.bashrc` so they persist.

---

## Codex multi-agent roles not working

1. Enable it: open Codex → `/experimental` → enable **Multi-agents** → restart Codex
2. Confirm `.codex/config.toml` is in your project root: `ls .codex/`
3. Confirm agent files exist: `ls .codex/agents/`
