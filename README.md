# shellmates

Your terminal. Multiple AI models. All talking to each other.

```
┌──────────────────────────┬──────────────────────────┬──────────────────────────┐
│  claude                  │  gemini                  │  codex                   │
│                          │                          │                          │
│  Planning phase 3...     │  Reading the plan...     │  Reading the plan...     │
│  Delegating to agents... │  Writing auth.py...      │  Writing tests...        │
│  Waiting for signals...  │  Tests passing ✓         │  All passing ✓           │
│  Nice. On to phase 4.    │  PHASE_COMPLETE: done    │  PHASE_COMPLETE: done    │
└──────────────────────────┴──────────────────────────┴──────────────────────────┘
```

Claude plans. Gemini builds. Codex verifies. They coordinate through your terminal using nothing but tmux — no APIs between them, no glue code, just agents passing messages like coworkers at adjacent desks.

---

## What

shellmates is a lightweight orchestration layer for your terminal. It connects Claude Code, Gemini CLI, and Codex in side-by-side tmux panes — Claude holds the plan and delegates, the others execute in parallel and signal back when done.

No new framework. No shared memory. No API calls between models. Just text in a terminal.

---

## Why

Every AI coding tool runs one model in one context. You hit a wall when the task gets big — context fills up, the model loses the thread, architectural decisions get buried in implementation noise.

shellmates splits the work the way a good team does:

- **One agent thinks.** Claude holds the plan, reviews the work, decides what's next. Uses [GSD](https://github.com/gsd-build/get-shit-done) to produce structured plans that sub-agents can execute without needing your entire conversation history.
- **Other agents build.** Gemini and Codex get a fresh context, a clear plan, and a specific job. They commit, signal done, and wait.
- **The terminal is the meeting room.** tmux `send-keys` delivers tasks. `capture-pane` reads the replies. That's the whole protocol.

---

## How it works

```
You describe what to build
        ↓
Claude plans it with /gsd:plan-phase  →  PLAN.md on disk
        ↓
Claude sends the plan to Gemini       →  tmux send-keys
Claude sends the plan to Codex        →  tmux send-keys  (in parallel)
        ↓
Gemini implements, tests, commits
Codex implements, tests, commits      (simultaneously)
        ↓
Both signal: PHASE_COMPLETE           →  Claude reads with capture-pane
        ↓
Claude reviews, decides next step
        ↓
repeat
```

The plan lives on disk. Sub-agents read it fresh every time. No conversation history required, no context bleed between agents, no awkward handoffs.

---

![shellmates demo](docs/demo.gif)

---

## Get started

**Point your AI agent at this:**

```
Read https://raw.githubusercontent.com/rs07-git/shellmates/main/INIT.md and set up shellmates for this project.
```

That's it. Your agent will install the tools, update your project files, fill in the config, and drop a personalized tutorial in your terminal. No manual steps required.

> Works with Claude Code, Gemini CLI, Codex, or any AI that can read a URL and run shell commands.

---

## Want to understand what's happening first?

**→ [QUICKSTART.md](QUICKSTART.md)** — step-by-step walkthrough you can follow yourself

---

## Mix and match

| Orchestrator | Executor(s) | Good for |
|---|---|---|
| Claude | Gemini | Large context tasks, Google Search grounding |
| Claude | Codex | Sandboxed execution, internal multi-agent roles |
| Claude | Gemini + Codex | Parallel tracks — implement and verify simultaneously |
| Claude | Multiple Gemini panes | Fan-out across many files at once |

---

## What's in the box

```
shellmates/
├── INIT.md                ← agent-executable setup (point your AI here)
├── QUICKSTART.md          ← human-readable setup guide
├── ORCHESTRATOR.md        ← Claude's operating instructions (copied to your project)
├── templates/
│   ├── CLAUDE.md          ← snippet added to your project's CLAUDE.md
│   ├── GEMINI.md          ← filled in and added to your project root
│   ├── AGENTS.md          ← for Codex
│   └── .codex/            ← Codex multi-agent role configs
├── scripts/
│   ├── launch.sh          ← spin up a 2-pane session
│   ├── launch-full-team.sh ← spin up a 4-pane session
│   └── monitor.sh         ← watch for signals in the background
└── docs/
    ├── WORKFLOW.md        ← the plan/execute split explained
    ├── PROTOCOL.md        ← full tmux IPC reference
    ├── ROLES.md           ← patterns and when to use each
    └── TROUBLESHOOTING.md
```

---

## The protocol in one paragraph

Claude sends a task by running `tmux send-keys -t pane "do X" Enter`. The sub-agent does the work and prints `PHASE_COMPLETE: Phase N — summary` when done. Claude reads the output with `tmux capture-pane -t pane -p | tail -20`. No framework, no SDK, no shared state. Just text in a terminal.

Full spec in [docs/PROTOCOL.md](docs/PROTOCOL.md).

---

## License

MIT
