# shellmates

Your terminal. Multiple AI agents. All talking to each other.

```
npm install -g shellmates
```

Claude plans. Gemini builds. Codex verifies. They coordinate through your terminal using tmux — no APIs between them, no glue code, just agents passing tasks like coworkers at adjacent desks.

---

![shellmates demo](docs/demo.gif)

---

## How it works

```
shellmates spawn --task "Add dark mode" --agent gemini
        ↓
shellmates opens a tmux pane, launches Gemini, hands it the task
        ↓
Gemini implements, tests, writes results to ~/.shellmates/inbox/
        ↓
Claude gets a native notification (no polling) → reads the result → decides what's next
        ↓
repeat
```

The agent runs in its own isolated tmux session. You stay in your pane. When it's done, Claude wakes up automatically via a PostToolUse hook — not because it kept checking.

---

## Get started

```bash
shellmates init          # create config and directories
shellmates install-hook  # wire up native Claude Code notifications (do this once)
shellmates config        # set your default agent and permission mode
```

Then dispatch a task:

```bash
shellmates spawn --task "Add dark mode to the settings page"
shellmates spawn --task-file plan.md --agent codex --watch
```

---

## Commands

| Command | What it does |
|---|---|
| `shellmates init` | First-time setup — create `~/.shellmates/` and default config |
| `shellmates config` | Change default agent, orchestrator, and permission mode |
| `shellmates spawn` | Dispatch a task to a worker agent in a new tmux session |
| `shellmates status` | Show active sessions, config, and inbox results |
| `shellmates install-hook` | Install the Claude Code PostToolUse hook for native notifications |
| `shellmates teardown` | Kill shellmates tmux sessions |
| `shellmates update` | Update to the latest version |

**Spawn options:**

```
-t, --task <text>       Inline task text
-f, --task-file <path>  Path to a task file
-a, --agent <name>      gemini | codex (overrides default)
-s, --session <name>    tmux session name
-p, --project <path>    Working directory for the agent (default: cwd)
-w, --watch             Wait and print result when agent finishes
```

---

## The notification hook

Without the hook, Claude has to poll for results — checking the inbox every few seconds, burning tokens doing nothing useful.

With `shellmates install-hook`, a PostToolUse hook script watches for inbox files in the background and uses Claude Code's `asyncRewake` mechanism to deliver a native notification when the agent finishes. Claude wakes up exactly once, reads the result, and moves on.

```bash
shellmates install-hook
```

Run it once. It installs `~/.claude/hooks/shellmates-notify.sh` and adds the hook entry to `~/.claude/settings.json` automatically.

---

## Mix and match

| Orchestrator | Worker(s) | Good for |
|---|---|---|
| Claude Code | Gemini CLI | Large context tasks, long-running implementations |
| Claude Code | Codex CLI | Sandboxed execution, isolated environments |
| Claude Code | Gemini + Codex | Parallel tracks — build and verify simultaneously |
| Claude Code | Multiple Gemini panes | Fan-out across many files or components |

---

## Requirements

- Node 18+
- tmux
- At least one of: [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Codex CLI](https://github.com/openai/codex)

---

## License

MIT
