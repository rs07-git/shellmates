# shellmates

Your terminal. Multiple AI models. All talking to each other.

```
┌─────────────────────────────┬─────────────────────────────┐
│  gemini                     │  claude                     │
│                             │                             │
│  Reading the plan...        │  Planning phase 3...        │
│  Writing auth.py...         │  Delegating to Gemini...    │
│  Tests passing ✓            │  Waiting for the signal...  │
│  PHASE_COMPLETE: auth done  │  Nice. On to phase 4.       │
└─────────────────────────────┴─────────────────────────────┘
```

Claude plans. Gemini builds. Codex verifies. They coordinate through your terminal using nothing but tmux — no APIs between them, no glue code, just agents passing messages like coworkers at adjacent desks.

That's shellmates.

---

## Why

Every AI coding tool runs one model in one context. You hit a wall when the task gets big — context fills up, the model loses the thread, architectural decisions get buried in implementation noise.

shellmates splits the work the way a good team does:

- **One agent thinks.** Claude holds the plan, reviews the work, decides what's next. Uses [GSD](https://github.com/obra/get-shit-done) to produce structured plans that sub-agents can execute without needing your entire conversation history.
- **Other agents build.** Gemini and Codex get a fresh context, a clear plan, and a specific job. They commit, signal done, and wait.
- **The terminal is the meeting room.** tmux `send-keys` delivers tasks. `capture-pane` reads the replies. That's the whole protocol.

You end up with parallel execution across providers, persistent orchestration that survives context resets, and a workflow that scales from one feature to a full product.

---

## What you need

```bash
brew install tmux

npm install -g @anthropic-ai/claude-code   # the orchestrator
npm install -g @google/gemini-cli          # a shellmate
npm install -g @openai/codex               # another shellmate (optional)

npx get-shit-done-cc@latest                # planning framework
```

And API keys for whichever providers you're using.

---

## Get started

**→ [QUICKSTART.md](QUICKSTART.md)**

Ten minutes from zero to your first orchestrated workflow.

---

## How it works

```
You describe what to build
        ↓
Claude plans it with /gsd:plan-phase  →  PLAN.md on disk
        ↓
Claude sends the plan to Gemini       →  tmux send-keys
        ↓
Gemini implements, tests, commits
        ↓
Gemini signals: PHASE_COMPLETE        →  Claude reads with capture-pane
        ↓
Claude reviews, decides next step
        ↓
repeat
```

The plan lives on disk. Sub-agents read it fresh every time. No conversation history required, no context bleed between agents, no awkward handoffs.

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
├── QUICKSTART.md          ← start here
├── ORCHESTRATOR.md        ← drop into your project (Claude's playbook)
├── templates/
│   ├── GEMINI.md          ← drop into your project (Gemini's playbook)
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

Claude sends a task by running `tmux send-keys -t pane "do X" Enter`. The sub-agent does the work and prints `PHASE_COMPLETE: Phase N — summary` when done. Claude polls with `tmux capture-pane -t pane -p | tail -20` to detect the signal. That's it. No framework, no SDK, no shared state. Just text in a terminal.

Full spec in [docs/PROTOCOL.md](docs/PROTOCOL.md).

---

## License

MIT
