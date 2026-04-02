# The Workflow — Why Plan Here, Execute There?

## The Core Problem

When you give a single AI agent a large task, two things tend to go wrong:

1. **Context drift** — after many edits the agent loses track of the original goal and starts making inconsistent decisions
2. **No separation of concerns** — the same agent that writes code also decides *what* to write, which means bad architectural decisions get implemented before anyone reviews them

The tmux-ai-orchestra pattern fixes both by splitting the job in two:

- **Claude** (orchestrator) thinks, plans, and reviews — but doesn't implement
- **Gemini / Codex** (executor) implements from a concrete plan — but doesn't decide scope

---

## The Full Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. YOU tell Claude what to build                               │
│     "Add user authentication with Google Sign-In"              │
│                         │                                       │
│  2. CLAUDE runs /gsd:plan-phase                                 │
│     → Produces .planning/phases/3-auth/PLAN.md                  │
│     → Contains: task list, files to touch, tests to write       │
│     → You review and approve the plan                           │
│                         │                                       │
│  3. CLAUDE delegates to Gemini                                  │
│     → tmux send-keys -t orchestra:0.0 "Execute Phase 3..."     │
│     → Gemini reads PLAN.md                                      │
│     → Gemini has full project context from GEMINI.md            │
│                         │                                       │
│  4. GEMINI executes                                             │
│     → Writes code, runs tests, fixes failures                   │
│     → Commits at each logical step                              │
│     → Outputs: PHASE_COMPLETE: Phase 3 — auth added, 14 pass   │
│                         │                                       │
│  5. CLAUDE reviews                                              │
│     → Reads Gemini's output (tmux capture-pane)                 │
│     → Checks git log for commits and what changed              │
│     → Runs /gsd:verify-work if needed                          │
│     → Reports to you: done / needs fix / proceed to phase 4    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## What GSD Adds

Without GSD you can still use this workflow — Claude just plans in plain text. But GSD makes it significantly better:

| Without GSD | With GSD |
|------------|---------|
| Claude improvises a plan in chat | Plans are structured PLAN.md files with tasks, files, and UAT criteria |
| No persistent state | `.planning/STATE.md` tracks exactly where you are across sessions |
| Plans live in chat history | Plans live on disk — sub-agents can read them directly |
| Hard to resume after a break | `/gsd:progress` restores full context in any session |
| No phase verification | `/gsd:verify-work` checks the implementation against the plan |

The key benefit: **Gemini reads the PLAN.md directly.** It doesn't need to understand your full conversation history. The plan is self-contained.

### Installing GSD

```bash
npx get-shit-done-cc@latest
```

This installs the GSD framework as Claude Code slash commands. After installing, restart Claude Code and run `/gsd:help` to see all available commands.

---

## Using This Without GSD

If you want to try the workflow before installing GSD, Claude can plan manually:

**Ask Claude to:**
```
Create a plan for [feature] as a markdown file at .planning/phases/1-feature/PLAN.md.
Include: task list, files to modify, test commands, and completion criteria.
Then delegate the plan to Gemini in pane orchestra:0.0.
```

This works fine for simple projects. GSD becomes more valuable as the project grows and you need persistent state across sessions.

---

## When Claude Does It vs. When Gemini Does It

**Let Gemini execute when:**
- The task spans many files (> 5)
- You want Claude's context free for reviewing
- You're running parallel tasks
- The implementation is mechanical (following a clear plan)
- The task will take more than 15–20 minutes

**Let Claude do it directly when:**
- The task is tiny (1–2 file changes)
- It requires judgment that's deeply tied to this conversation
- You're debugging something and the context is critical
- Gemini failed and you need to intervene

---

## The GEMINI.md File

This is the most important thing to get right. It's what Gemini reads when it starts — its entire understanding of your project comes from here.

A good GEMINI.md includes:
- What the project does (2-3 sentences)
- The tech stack and key dependencies
- Key file locations (entry points, services, schema)
- How to run tests and lint
- Code conventions (naming, commit format, etc.)
- The multi-agent protocol (the PHASE_COMPLETE signal, non-interactive rules)

When Gemini starts fresh in a new terminal, it has no memory of previous conversations. GEMINI.md is its only context. Keep it updated as your project evolves.

---

## The ORCHESTRATOR.md File

This tells Claude how to behave as an orchestrator. Drop it in your project root. Claude reads it at the start of each session and knows:
- Which panes contain which agents
- How to send tasks and read output
- The GSD command reference
- Rules about when to delegate vs. do it itself

---

## Handling Errors

If Gemini hits an error and stops:

1. Read what happened: `tmux capture-pane -t orchestra:0.0 -p -S -50 | tail -50`
2. Check if any commits were made: `git log --oneline -5`
3. Diagnose in Claude's pane — don't just retry the same task
4. Either send a corrective instruction to Gemini, or take over in Claude

If Gemini's output looks wrong after PHASE_COMPLETE:
1. Read the git diff: `git diff HEAD~1`
2. Tell Claude: *"Review what Gemini committed and tell me if it's correct"*
3. If it needs fixing: `tmux send-keys -t orchestra:0.0 "The previous implementation has an issue: [describe]. Please fix: [specific instructions]." Enter`

---

## Session Continuity

One of the best things about this setup: **you can leave and come back.**

- Claude's context resets when you close it — but `.planning/STATE.md` remembers where you were
- Gemini's context resets too — but GEMINI.md + PLAN.md have everything it needs
- The tmux session keeps running (panes stay alive when you detach)

To resume after a break:
```bash
tmux attach -t orchestra     # re-attach to running session
```

Then in Claude: `/gsd:progress` — Claude reads STATE.md and tells you exactly where you left off.
