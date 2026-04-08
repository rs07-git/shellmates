# Claude Code: Agent Swarm & Tmux Architecture Reference

This document provides a comprehensive technical breakdown of the **Agent Swarm (Team)** and **Tmux Integration** architecture found in Claude Code. It is intended as a reference for developers implementing similar multi-agent orchestration systems.

---

## 1. High-Level Architecture: The "Swarm"

Claude Code implements a **Multi-Process Swarm**. Each agent is an independent instance of the `claude` CLI. Coordination is achieved through a **Leader-Worker** model using asynchronous, file-based IPC.

### Key Concepts:
- **Leader:** The main session initiated by the user. It manages the team state, handles global permissions, and delegates tasks.
- **Teammate (Worker):** A separate process (usually in a tmux pane) that executes sub-tasks.
- **Subagent:** A special type of teammate that can run **in-process** (same Node.js process) using `AsyncLocalStorage` for context isolation.

---

## 2. Asynchronous Communication (Mailbox IPC)

The system uses the filesystem as a message broker. This ensures portability across different environments without requiring complex network sockets.

### File Structure:
- **Base Directory:** `~/.claude/teams/{team_name}/inboxes/`
- **Inbox File:** Each agent has a JSON file: `{agent_name}.json`.
- **Message Format:**
  ```json
  {
    "from": "sender_name",
    "text": "The message body (can be raw text or a structured JSON string)",
    "timestamp": "ISO-8601",
    "read": false,
    "color": "blue",
    "summary": "Short preview of the message"
  }
  ```

### Protocol Messages:
Structured JSON strings are passed through the `text` field for internal protocol coordination:
- `permission_request`: Workers ask the leader for permission to run a tool.
- `permission_response`: Leader approves/denies a worker's request.
- `plan_approval_request`: Worker submits a `PLAN.md` for review.
- `plan_approval_response`: Leader allows the worker to transition from "Plan Mode" to "Execution Mode."
- `idle_notification`: Sent by a worker when it completes a turn, including a summary of work.
- `shutdown_request`: Leader asks a worker to exit gracefully.

### Reference Files:
- `utils/teammateMailbox.ts`: Core mailbox implementation (read/write/locking).
- `hooks/useInboxPoller.ts`: React hook that polls the mailbox every 1s and routes messages to the correct UI or logic handler.

---

## 3. Tmux Integration (Display & Execution)

Tmux is the "Window Manager" for the swarm. It provides the visual layout and process isolation for terminal-based agents.

### The Tmux Backend (`TmuxBackend.ts`):
- **Socket Management:** Uses `tmux -L {swarm_socket}` to isolate the swarm session if the user is not already in tmux.
- **Pane Creation:** Uses `tmux split-window` to add teammates.
  - **Layout:** Typically uses `main-vertical`. The leader is pinned to the left (30%), and workers are tiled on the right (70%).
- **Identity Injection:** Teammates are started by injecting the CLI command into the pane:
  `cd {cwd} && env {inherited_env} claude --agent-id {id} --team-name {name} ...`
- **Visual Styling:**
  - **Titles:** `tmux select-pane -T {name}`
  - **Borders:** `tmux set-option -p pane-border-status top`
  - **Colors:** `tmux select-pane -P "bg=default,fg={color}"`

### Pane Backend Executor:
Adapts the raw Tmux commands to a standard `TeammateExecutor` interface, allowing the leader to treat a terminal pane as a manageable agent object.

### Reference Files:
- `utils/swarm/backends/TmuxBackend.ts`: Implementation of tmux CLI interactions.
- `utils/swarm/backends/PaneBackendExecutor.ts`: Adapts panes to the agent executor interface.
- `utils/swarm/backends/registry.ts`: Manages different backends (Tmux, iTerm2, In-Process).

---

## 4. State & Identity Management

### The Team File (`config.json`):
Located at `~/.claude/teams/{team_name}/config.json`.
- **Schema:**
  - `leadAgentId`: The ID of the orchestrator.
  - `members`: Array of objects tracking `agentId`, `name`, `color`, `tmuxPaneId`, `worktreePath`, and `isActive`.
  - `teamAllowedPaths`: List of directories where *all* teammates are pre-approved to work.

### Identity Resolution:
Agents resolve their identity on startup by checking (in order):
1. `AsyncLocalStorage` (for in-process subagents).
2. CLI flags (`--agent-id`, `--team-name`).
3. Environment variables.

### Reference Files:
- `utils/swarm/teamHelpers.ts`: CRUD operations for the `config.json` file.
- `utils/teammate.ts`: Global helpers for `isTeammate()`, `getAgentId()`, `getAgentName()`.

---

## 5. Filesystem Parallelism: Git Worktrees

To allow multiple agents to modify the codebase simultaneously without merge conflicts or clobbering each other's local state:
- **Strategy:** Each teammate is assigned a unique **Git Worktree**.
- **Implementation:** `git worktree add ../worktrees/{agent_name} {branch}`.
- **Cleanup:** The worktree is automatically removed when the agent session ends.

### Reference Files:
- `utils/swarm/teamHelpers.ts`: Contains `destroyWorktree()` logic.

---

## 6. Lifecycle: From Spawn to Shutdown

### 1. Spawning (`spawnUtils.ts`)
The leader gathers current session state (Model, Permission Mode, Env Vars) and builds a `spawn` command. It ensures the worker inherits the leader's context so they act consistently.

### 2. Initialization (`teammateInit.ts`)
When the worker starts, it:
- Reads the team `config.json`.
- Loads team-wide allowed paths into its own permission engine.
- Registers a `Stop` hook to notify the leader when it finishes a task.

### 3. Permission Bridging (`leaderPermissionBridge.ts`)
If a worker (especially an in-process one) needs permission, it "bridges" the request back to the leader's UI. The user sees a confirmation dialog on the leader's screen, even though the worker requested it.

### 4. Graceful Shutdown
1. Leader sends `shutdown_request` via mailbox.
2. Worker finishes its current turn.
3. Worker sends `shutdown_approved` back to the leader.
4. Leader (or Worker's own poller) kills the tmux pane and cleans up the worktree.

---

## 7. Recommended Reference Files for Implementation

| File Path | Purpose |
| :--- | :--- |
| `utils/swarm/backends/TmuxBackend.ts` | **Essential:** How to script tmux for pane management and styling. |
| `utils/teammateMailbox.ts` | **Essential:** The file-based IPC (mailbox) logic and locking. |
| `hooks/useInboxPoller.ts` | How to poll the mailbox and route different protocol message types. |
| `utils/swarm/teamHelpers.ts` | Team state management, `config.json` schema, and worktree cleanup. |
| `utils/swarm/spawnUtils.ts` | How to pass environment and flags from leader to worker. |
| `utils/swarm/backends/PaneBackendExecutor.ts` | The bridge between the CLI process and the Tmux pane. |
| `utils/teammate.ts` | Identity resolution logic (Who am I? What is my team?). |
| `utils/swarm/teammateInit.ts` | Teammate startup logic and global hook registration. |
| `utils/swarm/leaderPermissionBridge.ts` | Handling cross-agent permission requests. |

---

## 8. The Bridge Architecture (GUI & Remote SDK)

The `bridge` is a sophisticated abstraction layer that decouples the core agent engine from the user interface. It transforms the terminal-based REPL into a platform-agnostic SDK.

### Key Learnings for ShellMates:
- **Asynchronous Transport:** The `replBridgeTransport.ts` abstracts whether the agent is talking to a local TTY, a WebSocket, or an SSE (Server-Sent Events) stream. This is essential if you want a `shellmates` web dashboard.
- **Ingress/Egress Filtering:** `bridgeMessaging.ts` filters internal "REPL chatter" (like progress indicators or intermediate tool results) so the external UI only sees clean `user` and `assistant` turns.
- **Control Requests:** The bridge allows the agent to send "Permission Requests" (`can_use_tool`) to a remote UI. The agent pauses its execution loop, the bridge sends a JSON payload to the UI, and the agent resumes once it receives a `control_response`.

### Reference Files (V2):
- `src/bridge/replBridge.ts`: The main entry point for the agent-to-external bridge.
- `src/bridge/bridgeMessaging.ts`: Logic for parsing and routing SDK messages.
- `src/bridge/replBridgeTransport.ts`: The interface for different communication channels (WS, SSE).

---

## 9. Model Context Protocol (MCP) Server

V2 includes a standalone MCP Server. This turns the agent's internal tools into a "Service" that other agents can consume.

### Key Learnings for ShellMates:
- **Tool Discovery:** Instead of hardcoding tools, the MCP server allows an external agent (like Claude Desktop) to call `list_tools`.
- **Cross-Agent Collaboration:** A "Leader" agent in one IDE can use the "Tools" of a `shellmates` agent running in another process via the MCP bridge.
- **Prompt Templates:** The server exposes "Prompts" (e.g., `explain_tool`, `architecture_overview`) that help the LLM understand how to use the complex system without massive context-window bloat.

### Reference Files (V2):
- `mcp-server/src/server.ts`: The core MCP server implementation using `@modelcontextprotocol/sdk`.
- `mcp-server/src/http.ts`: Exposing MCP tools over HTTP/SSE for remote access.

---

## 10. Observability: Monitoring the Swarm

V2 introduces infrastructure for monitoring the health and performance of the agent team.

- **Telemetry:** Uses Prometheus and Grafana to track metrics like `tengu_agent_turns_total`, `tengu_tool_use_count`, and `tengu_token_usage`.
- **Health Checks:** A dedicated `/health` endpoint in the bridge/MCP server allows a load balancer or a "Watchdog" agent to restart stalled teammates.

### Reference Files (V2):
- `grafana/`: Dashboards for visualizing agent performance.
- `prometheus/`: Configuration for scraping metrics from the running swarm.

---

## 11. Development Roadmap for MAS (Multi-Agent System)

1. **Step 1: The Core Loop.** Build the mailbox poller and basic "Spawn" capability using a simple `split-window`.
2. **Step 2: Protocols.** Implement `permission_request` and `idle_notification` to coordinate basic turns.
3. **Step 3: Worktrees.** Add `git worktree` support to enable true parallel execution.
4. **Step 4: Safety.** Implement "Plan Mode" logic where workers must wait for a specific mailbox response before unlocking write tools.
5. **Step 5: Visual Polish.** Add the Tmux border and color styling for a professional DX.
6. **Step 6: The Bridge.** Add a WebSocket bridge to allow a web-based "Control Tower" UI.
7. **Step 7: MCP Integration.** Expose `shellmates` tools as an MCP server so other IDEs can trigger swarm actions.