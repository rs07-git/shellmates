# shellmates

<div align="center">
  <img src="docs/screenshot.png" alt="shellmates CLI" width="720" />
</div>

<br />

<div align="center">
  <strong>Your terminal. Multiple AI agents. All talking to each other.</strong>
</div>

<br />

```bash
npm install -g shellmates
```

Claude plans. Gemini builds. Codex verifies. They coordinate through your terminal using tmux — no APIs between them, no glue code, just agents passing tasks like coworkers at adjacent desks.

---

<div align="center">
  <img src="docs/demo.gif" alt="shellmates demo" width="720" />
</div>

---

## How it works

You describe what you want. Shellmates breaks it into tasks and dispatches them to AI agent executors running in tmux panes. When an agent finishes, your orchestrator gets notified — no polling, no waiting, no manual checking.

```
you describe the goal
        ↓
Claude (orchestrator) plans and dispatches tasks via shellmates spawn
        ↓
Gemini / Codex (worker) implements the task in its own tmux pane
        ↓
worker writes result to ~/.shellmates/inbox/
        ↓
Claude gets a native notification → reads result → decides what's next
        ↓
repeat until done
```

Each worker runs in an isolated tmux pane. You stay in your pane. The orchestrator wakes up automatically via a PostToolUse hook — not because it kept checking.

---

## Get started

**1. Install and initialize:**

```bash
npm install -g shellmates
shellmates init          # create ~/.shellmates/ and default config
shellmates install-hook  # wire up native Claude Code notifications (once)
shellmates config        # choose your agent(s), orchestrator, and permission mode
```

**2. Start a session:**

```bash
shellmates spawn          # natural-language intake — Claude asks what you want to work on
```

Or dispatch directly:

```bash
shellmates spawn --task "Add dark mode to the settings page"
shellmates spawn --task "Refactor the auth module" --agent codex
shellmates spawn --task-file plan.md --agent gemini --watch
```

---

## Two ways to use shellmates

### Pond mode — let Claude drive

```bash
shellmates spawn
```

Opens an orchestrator session (Claude by default). Claude greets you, asks what you want to build, and handles all the dispatching. You just describe the goal and review results as they come in.

### Direct dispatch — you drive

```bash
shellmates spawn --task "Add pagination to the API" --agent gemini
```

You send a specific task directly to a worker agent. Good when you already know exactly what you want done and don't need planning.

---

## Commands

| Command | What it does |
|---|---|
| `shellmates init` | First-time setup — create `~/.shellmates/` and default config |
| `shellmates config` | Change default agent(s), orchestrator, and permission modes |
| `shellmates spawn` | Start a pond session or dispatch a task directly to a worker |
| `shellmates status` | Show active sessions, config, and inbox results |
| `shellmates install-hook` | Install the Claude Code PostToolUse hook for native notifications |
| `shellmates teardown` | Kill all shellmates tmux sessions |
| `shellmates update` | Update to the latest version |

**Spawn options:**

```
-t, --task <text>         Inline task text
-f, --task-file <path>    Path to a task file
-a, --agent <name>        gemini | codex (overrides default)
-s, --session <name>      tmux session name
-p, --project <path>      Working directory for the agent (default: cwd)
-w, --watch               Wait and print result when agent finishes
-r, --reuse-pane <paneId> Reuse a warm agent pane instead of spawning a new one
```

---

## Reusing warm agent panes

When an agent finishes a task, its pane stays alive — the agent is still loaded, context still warm. Instead of spinning up a fresh agent for the next task (slow cold start), you can reuse it:

```bash
# First task — spawns a new pane
shellmates spawn --task "Write the API endpoint" --agent gemini

# Agent finishes → you receive an AGENT_PING with the pane ID:
# AGENT_PING: job:job-123 reuse-pane:%46 status:complete RESULT: ...

# Follow-up task — reuses the warm pane, sends /clear to reset context
shellmates spawn --task "Write tests for the endpoint" --agent gemini --reuse-pane %46
```

Use `--reuse-pane` for sequential tasks. Spawn fresh when you need two agents running in parallel.

---

## The notification hook

Without the hook, the orchestrator has to poll for results — checking the inbox every few seconds, burning tokens doing nothing.

With `shellmates install-hook`, a PostToolUse hook watches for inbox files in the background and uses Claude Code's native `asyncRewake` mechanism to deliver a notification the moment an agent finishes. The orchestrator wakes up exactly once, reads the result, and moves on.

```bash
shellmates install-hook
```

Run it once. It installs `~/.claude/hooks/shellmates-notify.sh` and adds the hook entry to `~/.claude/settings.json` automatically.

---

## Configuration

```bash
shellmates config
```

| Setting | Options | Default |
|---|---|---|
| Default agent(s) | `gemini`, `codex` | `gemini` |
| Orchestrator | `claude`, `gemini`, `codex` | `claude` |
| Worker permission mode | `default`, `bypass` | `default` |
| Orchestrator permission mode | `default`, `bypass` | `default` |

**Permission modes:**
- `default` — agents ask before modifying files or running commands
- `bypass` — agents run fully autonomously. Workers: `gemini --yolo`, `codex --full-auto`. Orchestrator: `claude --dangerously-skip-permissions`, `gemini --yolo`, `codex --full-auto`

Worker and orchestrator permission modes are set independently — you can run a cautious orchestrator with autonomous workers, or vice versa.

---

## Mix and match

| Orchestrator | Worker(s) | Good for |
|---|---|---|
| Claude Code | Gemini CLI | Large-context tasks, long-running implementations |
| Claude Code | Codex CLI | Sandboxed execution, isolated environments |
| Claude Code | Gemini + Codex | Parallel tracks — build and verify simultaneously |
| Claude Code | Multiple Gemini panes | Fan-out across many files or components |
| Gemini CLI | Codex CLI | Gemini-native orchestration |
| Codex CLI | Gemini CLI | Codex-native orchestration |

---

## Requirements

- Node 18+
- tmux (`brew install tmux`)
- At least one of: [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Codex CLI](https://github.com/openai/codex)
- For pond mode notifications: [Claude Code](https://claude.ai/code)

---

## License

MIT
