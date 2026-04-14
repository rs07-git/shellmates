import chalk from 'chalk'
import { spawnSync } from 'child_process'
import { existsSync, readFileSync, writeFileSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { tmpdir, homedir } from 'os'
import { readConfig, CONFIG_PATH } from '../utils/config.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const SCRIPTS_DIR = join(__dirname, '..', '..', 'scripts')
const INBOX_DIR = join(homedir(), '.shellmates', 'inbox')

export async function spawn(options = {}) {
  if (!existsSync(CONFIG_PATH)) {
    console.log(chalk.yellow('\n  ~ Not initialized yet.'))
    console.log('  Run ' + chalk.bold('shellmates init') + ' first.\n')
    process.exit(1)
  }

  const config = readConfig()

  // Resolve agents: --agent flag (single) overrides config; config may have array
  let agents
  if (options.agent) {
    agents = [options.agent]
  } else {
    // Support both old default_agent and new default_agents
    agents = config.default_agents
      || (config.default_agent ? [config.default_agent] : ['gemini'])
  }

  const ts = Date.now()
  const project = options.project || process.cwd()
  const noPing = options.noPing || false

  // Resolve task file
  let taskFile = options.taskFile
  if (!taskFile && options.task) {
    const tmp = join(tmpdir(), `shellmates-task-${ts}.txt`)
    writeFileSync(tmp, options.task)
    taskFile = tmp
  }

  if (!taskFile || !existsSync(taskFile)) {
    console.error(chalk.red('  ✗ No task provided. Use --task "..." or --task-file path'))
    process.exit(1)
  }

  const parallel = agents.length > 1

  console.log('')
  console.log(chalk.bold('  Shellmates — Spawning'))
  console.log(chalk.dim('  ─────────────────────────────────────'))
  if (parallel) {
    console.log(chalk.dim('  Agents:  ') + chalk.bold(agents.join(' + ')))
    console.log(chalk.dim('  Mode:    parallel'))
  } else {
    console.log(chalk.dim('  Agent:   ') + chalk.bold(agents[0]))
  }
  console.log(chalk.dim('  Perms:   ') + chalk.bold(config.permission_mode))
  console.log('')

  const spawnScript = join(SCRIPTS_DIR, 'spawn-team.sh')
  const sessions = []

  for (const agent of agents) {
    const session = options.session
      ? (agents.length > 1 ? `${options.session}-${agent}` : options.session)
      : `shellmates-${agent}-${ts}`

    const args = [
      '--task-file', taskFile,
      '--project', project,
      '--session', session,
      '--agent', agent,
    ]
    if (noPing) args.push('--no-ping')
    if (options.reusePane) args.push('--reuse-pane', options.reusePane)

    const result = spawnSync('bash', [spawnScript, ...args], { stdio: 'inherit' })

    if (result.status !== 0) {
      console.error(chalk.red(`\n  ✗ Spawn failed for ${agent}`))
      process.exit(result.status || 1)
    }

    sessions.push(session)
  }

  if (parallel) {
    console.log('')
    console.log(chalk.dim('  Sessions:'))
    for (const s of sessions) {
      console.log(chalk.dim('    • ') + s)
    }
  }

  if (options.watch) {
    await watchInbox(sessions)
  }
}

async function watchInbox(sessions) {
  const { readdir } = await import('fs/promises')
  console.log('')
  console.log(chalk.dim('  Watching for results...  (Ctrl+C to stop)'))

  const before = new Set(existsSync(INBOX_DIR)
    ? (await readdir(INBOX_DIR)).filter(f => f.endsWith('.txt'))
    : [])

  const remaining = new Set(sessions)
  let elapsed = 0
  const timeout = 300

  while (elapsed < timeout && remaining.size > 0) {
    await new Promise(r => setTimeout(r, 2000))
    elapsed += 2
    if (!existsSync(INBOX_DIR)) continue
    const after = (await readdir(INBOX_DIR)).filter(f => f.endsWith('.txt'))
    const newFiles = after.filter(f => !before.has(f))
    for (const f of newFiles) {
      const content = readFileSync(join(INBOX_DIR, f), 'utf8')
      const matchingSession = sessions.find(s => f.includes(s))
      console.log('')
      console.log(chalk.green('  ✓ Result received') + chalk.dim(` (${matchingSession || f})`))
      console.log('')
      for (const line of content.trim().split('\n')) {
        const [key, ...rest] = line.split(':')
        console.log('  ' + chalk.dim(key + ':') + ' ' + rest.join(':').trim())
      }
      if (matchingSession) remaining.delete(matchingSession)
      before.add(f)
    }
  }

  if (remaining.size > 0) {
    console.log(chalk.yellow('\n  ~ Timed out waiting for: ' + [...remaining].join(', ')))
  }
}
