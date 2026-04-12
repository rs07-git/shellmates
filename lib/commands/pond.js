import chalk from 'chalk'
import { writeFileSync, chmodSync, existsSync } from 'fs'
import { join } from 'path'
import { tmpdir, homedir } from 'os'
import { execSync, spawnSync } from 'child_process'
import { readConfig, CONFIG_PATH } from '../utils/config.js'
import { tmuxAvailable } from '../utils/tmux.js'

const ORCHESTRATOR_CMDS = {
  claude: (promptFile) => `claude "$(cat ${promptFile})"`,
  gemini: (promptFile) => `gemini -p "$(cat ${promptFile})"`,
}

function buildPrompt(agents, project) {
  const agentList = agents.join(', ')
  const projectNote = project ? `The user's project is at: ${project}` : ''

  return `You are the shellmates orchestrator — a coordinating AI that helps users accomplish software development goals by delegating work to specialized AI agent executors.

Your job is NOT to write code yourself. You plan, clarify, and dispatch.

Start with a single warm, brief greeting and ask the user what they want to work on today. Keep it to one or two sentences — don't explain your role, just start the conversation naturally.

When the user shares their goal:
1. Ask clarifying questions if needed (scope, affected files, tech stack, constraints)
2. Once you have enough context, break the work into discrete, self-contained tasks
3. Dispatch each task using the Bash tool: shellmates spawn --task "precise task description" --agent <agent>
4. When an executor finishes you'll receive an AGENT_PING in your terminal — review the result, then decide what comes next
5. Repeat until the goal is complete

Dispatch rules:
- Only spawn when you have a specific, actionable task — not vague intentions
- gemini: best for large-context work, long implementations, reading many files
- codex: best for sandboxed execution, isolated environments, focused rewrites
- You can dispatch multiple agents in parallel if tasks are truly independent
- Never spawn the same task twice — verify before re-dispatching

Available agents: ${agentList}
Dispatch command: shellmates spawn --task "..." --agent gemini|codex
Check sessions: shellmates status
${projectNote}`
}

export async function pond(options) {
  if (!existsSync(CONFIG_PATH)) {
    console.log(chalk.yellow('\n  ~ Not initialized yet.'))
    console.log('  Run ' + chalk.bold('shellmates init') + ' first.\n')
    process.exit(1)
  }

  if (!tmuxAvailable()) {
    console.log(chalk.red('\n  ✗ tmux not found. Install: brew install tmux\n'))
    process.exit(1)
  }

  const config = readConfig()
  const orchestrator = config.orchestrator || 'claude'
  const agents = config.default_agents || (config.default_agent ? [config.default_agent] : ['gemini'])
  const project = options.project || process.cwd()

  if (!ORCHESTRATOR_CMDS[orchestrator]) {
    console.log(chalk.red(`\n  ✗ Orchestrator "${orchestrator}" doesn't support pond mode yet.`))
    console.log(chalk.dim('  Set orchestrator to "claude" in shellmates config.\n'))
    process.exit(1)
  }

  const ts = Date.now()
  const sessionName = options.session || `shellmates-pond-${ts}`

  // Write prompt to temp file (avoids shell escaping issues)
  const promptFile = join(tmpdir(), `shellmates-pond-${ts}.txt`)
  writeFileSync(promptFile, buildPrompt(agents, project))

  // Write launcher script
  const launchFile = join(tmpdir(), `shellmates-pond-${ts}.sh`)
  const orchCmd = ORCHESTRATOR_CMDS[orchestrator](promptFile)
  writeFileSync(launchFile, `#!/bin/bash\ncd ${JSON.stringify(project)}\n${orchCmd}\n`)
  chmodSync(launchFile, 0o755)

  console.log('')
  console.log(chalk.bold('  Shellmates — Pond'))
  console.log(chalk.dim('  ─────────────────────────────────────'))
  console.log(chalk.dim('  Orchestrator: ') + chalk.bold(orchestrator))
  console.log(chalk.dim('  Agents:       ') + chalk.bold(agents.join(', ')))
  console.log(chalk.dim('  Project:      ') + chalk.dim(project))
  console.log(chalk.dim('  Session:      ') + chalk.dim(sessionName))
  console.log('')
  console.log(chalk.dim('  Starting pond... attach with Ctrl+A (or configured prefix)'))
  console.log('')

  // Create detached tmux session
  try {
    execSync(`tmux new-session -d -s ${JSON.stringify(sessionName)} -x 220 -y 50`, { stdio: 'ignore' })
  } catch {
    console.log(chalk.red(`  ✗ Could not create tmux session (already exists?)`))
    console.log(chalk.dim(`    Try: tmux attach -t ${sessionName}\n`))
    process.exit(1)
  }

  // Launch orchestrator
  execSync(`tmux send-keys -t ${JSON.stringify(sessionName)} ${JSON.stringify(launchFile)} Enter`)

  // Attach — this takes over the terminal
  spawnSync('tmux', ['attach-session', '-t', sessionName], { stdio: 'inherit' })
}
