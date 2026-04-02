# tmux-ai-orchestra

**Multi-provider AI orchestration in your terminal.**

Run Claude Code as a planning orchestrator while Gemini CLI and/or Codex execute the work — all in one tmux session, coordinating through terminal I/O.

```
┌──────────────────────────────────┬──────────────────────────────────┐
│  GEMINI CLI       (pane 0.0)     │  CLAUDE CODE      (pane 0.1)     │
│  sub-agent / executor            │  orchestrator / planner          │
│                                  │                                  │
│  > Reading PLAN.md...            │  > /gsd:plan-phase 3             │
│  > Implementing auth endpoint    │  > Plan ready. Delegating...     │
│  > Running tests... ✓            │  > Waiting for PHASE_COMPLETE    │
│  PHASE_COMPLETE: Phase 3 done    │  > Reviewing output...           │
│  AWAITING_INSTRUCTIONS           │  > Next: Phase 4                 │
└──────────────────────────────────┴──────────────────────────────────┘
```

---

## The Idea

Most AI coding tools either plan *or* execute, but not both cleanly. This setup splits the work:

- **Claude Code** (right pane) — thinks, plans, coordinates. Uses the [GSD framework](https://github.com/obra/get-shit-done) to create structured plans. Reviews output. Decides what's next.
- **Gemini CLI / Codex** (left pane) — executes. Reads the plan, writes code, runs tests, commits. Reports back.

The two agents communicate through tmux: Claude sends tasks via `tmux send-keys`, sub-agents signal completion with a `PHASE_COMPLETE:` line, and Claude reads their output with `tmux capture-pane`.

This mirrors how Claude Code works internally with its sub-agents — but lets you bring in **any AI provider** as the executor.

---

## Prerequisites

- macOS or Linux with [tmux](https://github.com/tmux/tmux) installed
- [Claude Code](https://claude.ai/code) with an Anthropic API key
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) with a Google API key (or [Codex CLI](https://github.com/openai/codex) with an OpenAI key)
- [GSD framework](https://github.com/obra/get-shit-done) — the planning layer that makes this workflow powerful

---

## Quickstart

**→ [QUICKSTART.md](QUICKSTART.md) — get running in 10 minutes**

---

## How the Workflow Flows

```
You tell Claude what to build
        │
        ▼
Claude runs /gsd:plan-phase        ← structured plan in .planning/phases/
        │
        ▼
Claude delegates plan to Gemini    ← tmux send-keys with plan context
        │
        ▼
Gemini executes, commits           ← reads plan, writes code, runs tests
        │
        ▼
Gemini signals PHASE_COMPLETE      ← Claude polls with capture-pane
        │
        ▼
Claude reviews + decides next step ← check git log, read output, continue
```

---

## Files in This Package

```
tmux-ai-orchestra/
├── QUICKSTART.md                  ← start here
├── ORCHESTRATOR.md                ← drop into your project (Claude's instructions)
├── README.md                      ← this file
│
├── scripts/
│   ├── launch.sh                  ← start a 2-pane session
│   ├── launch-full-team.sh        ← start a 4-pane session
│   └── monitor.sh                 ← background watcher
│
├── templates/
│   ├── GEMINI.md                  ← drop into your project (Gemini's instructions)
│   ├── AGENTS.md                  ← drop into your project (Codex's instructions)
│   └── .codex/                    ← Codex multi-agent role definitions
│
└── docs/
    ├── WORKFLOW.md                ← deep dive on the plan/execute split
    ├── PROTOCOL.md                ← full tmux IPC reference
    ├── ROLES.md                   ← when to use each agent/pattern
    └── TROUBLESHOOTING.md         ← common issues and fixes
```

---

## License

MIT
