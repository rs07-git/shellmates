# Roles and Patterns

## The Two Roles

### Orchestrator — Claude Code

**Does:** Plans with GSD, delegates tasks, monitors completion, reviews output, decides next steps.

**Does NOT do:** Implement features directly (except small tasks under ~5 files).

**Why Claude as orchestrator?**
- Persistent context across the session — knows the full picture
- GSD framework integration for structured planning
- Can review sub-agent output and catch errors
- Doesn't get confused by implementation details it didn't write

---

### Sub-agent — Gemini CLI

**Does:** Receives a task, reads the plan, implements it, commits, signals PHASE_COMPLETE.

**Does NOT do:** Decide scope, break down requirements, or remember previous sessions.

**Why Gemini as executor?**
- 1M token context window — can hold large plans and codebases
- Fast at mechanical implementation tasks
- Can run tests and fix failures autonomously
- Separate context from Claude — implementation details don't pollute the orchestrator

**Why Codex as executor (alternative)?**
- Native multi-agent spawning (internal planner/researcher/executor/verifier roles)
- Good for tasks that need internal parallelism
- Access to OpenAI models

---

## Patterns

### Pattern 1: Plan → Delegate → Review (most common)

Best for: Any task > 15 minutes or > 5 files.

```
Claude: /gsd:plan-phase 3
Claude: [reviews plan]
Claude: tmux send-keys -t orchestra:0.0 "Execute Phase 3 per PLAN.md..."
Gemini: [implements, commits]
Gemini: PHASE_COMPLETE: Phase 3 — auth added
Claude: [reads output, checks git, reports]
```

---

### Pattern 2: Parallel execution

Best for: Independent tasks with no shared files.

```
Claude: tmux send-keys -t full:0.0 "Task A: add GET /users..."
Claude: tmux send-keys -t full:0.2 "Task B: add GET /posts..."
[both run simultaneously]
Claude: [polls both panes every 30s]
Claude: [synthesizes results when both complete]
```

Rule: never parallel-assign tasks that touch the same files.

---

### Pattern 3: Research → Plan → Execute

Best for: Tasks where you're uncertain about implementation approach.

```
Claude: tmux send-keys -t orchestra:0.0 "Research how to implement OAuth2 
  with Google in this FastAPI app. Read the existing auth code first.
  Return a summary of the approach and any risks."
Gemini: [reads code, returns analysis]
Claude: [reads Gemini's analysis via capture-pane]
Claude: /gsd:plan-phase 3   [informed by the research]
Claude: tmux send-keys -t orchestra:0.0 "Execute Phase 3 per PLAN.md..."
```

---

### Pattern 4: Fan-out audit

Best for: Applying the same check to many files.

```
Claude: [loops through file list]
Claude: tmux send-keys -t full:0.0 "Audit api/users.py for security issues..."
Claude: tmux send-keys -t full:0.2 "Audit api/posts.py for security issues..."
Claude: tmux send-keys -t full:0.3 "Audit api/auth.py for security issues..."
[all run in parallel]
Claude: [collects all outputs, ranks findings]
```

---

### Pattern 5: Fix-forward

Best for: When Gemini's output is mostly right but needs a small correction.

```
Gemini: PHASE_COMPLETE: Phase 3 — auth added
Claude: [reads output — sees one test is failing]
Claude: tmux send-keys -t orchestra:0.0 "The test test_auth_invalid_token is failing.
  Read the error, fix it, commit, and output PHASE_COMPLETE again."
Gemini: [fixes, re-commits]
Gemini: PHASE_COMPLETE: Phase 3 — auth fixed, all 14 tests pass
```

---

## Choosing Gemini vs. Codex

| Situation | Use |
|-----------|-----|
| Large codebase context needed | Gemini (1M token window) |
| Task needs internal research + plan + execute | Codex (multi-agent roles) |
| Google Search grounding helpful | Gemini |
| You want independent verification built in | Codex (verifier role) |
| Fastest time-to-working-code | Either — test both |
| You only have one API key | Whatever you have |

---

## Codex Role Reference

Configured in `.codex/config.toml`. Invoke a role by mentioning it in your task:

```
Run a [researcher] then [executor] workflow for this task: ...
```

| Role | What it does |
|------|-------------|
| `researcher` | Read-only — discovers constraints and unknowns before implementation |
| `planner` | Produces a structured PLAN.md from task description + codebase |
| `executor` | Implements an approved plan with minimal blast radius |
| `verifier` | Independently tests and validates completed work |
| `reviewer` | Reviews diffs for bugs, security issues, regressions |
| `explorer` | Read-only codebase mapping — lists dependencies and callers |
| `worker` | Targeted single-task implementation |
