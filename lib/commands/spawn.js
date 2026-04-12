import chalk from 'chalk'
import { spawnSync } from 'child_process'
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { tmpdir, homedir } from 'os'
import { readConfig, CONFIG_PATH } from '../utils/config.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const SCRIPTS_DIR = join(__dirname, '..', '..', 'scripts')
const INBOX_DIR = join(homedir(), '.shellmates', 'inbox')

export async function spawn(options) {
  if (!existsSync(CONFIG_PATH)) {
    console.log(chalk.yellow('\n  ~ Not initialized yet.'))
    console.log('  Run ' + chalk.bold('shellmates init') + ' first.\n')
    process.exit(1)
  }

  const config = readConfig()

  const agent = options.agent || config.default_agent
  const session = options.session || `shellmates-${Date.now()}`
  const project = options.project || process.cwd()
  const noPing = options.noPing || false

  // Resolve task content
  let taskFile = options.taskFile
  if (!taskFile && options.task) {
    // Inline task string → write to temp file
    const tmp = join(tmpdir(), `shellmates-task-${Date.now()}.txt`)
    writeFileSync(tmp, options.task)
    taskFile = tmp
  }

  if (!taskFile || !existsSync(taskFile)) {
    console.error(chalk.red('  ✗ No task provided. Use --task "..." or --task-file path'))
    process.exit(1)
  }

  console.log('')
  console.log(chalk.bold('  Shellmates — Spawning'))
  console.log(chalk.dim('  ─────────────────────────────────────'))
  console.log(chalk.dim('  Agent:   ') + chalk.bold(agent))
  console.log(chalk.dim('  Session: ') + chalk.bold(session))
  console.log(chalk.dim('  Mode:    ') + chalk.bold(config.permission_mode))
  console.log('')

  const spawnScript = join(SCRIPTS_DIR, 'spawn-team.sh')
  const args = [
    '--task-file', taskFile,
    '--project', project,
    '--session', session,
    '--agent', agent,
  ]
  if (noPing) args.push('--no-ping')

  const result = spawnSync('bash', [spawnScript, ...args], { stdio: 'inherit' })

  if (result.status !== 0) {
    console.error(chalk.red('\n  ✗ Spawn failed'))
    process.exit(result.status || 1)
  }

  // If --watch, tail the inbox until the job file appears
  if (options.watch) {
    await watchInbox(session)
  }
}

async function watchInbox(session) {
  const { readdir } = await import('fs/promises')
  console.log('')
  console.log(chalk.dim('  Watching for result...  (Ctrl+C to stop)'))

  const before = new Set(existsSync(INBOX_DIR)
    ? (await readdir(INBOX_DIR)).filter(f => f.endsWith('.txt'))
    : [])

  let elapsed = 0
  const timeout = 300
  while (elapsed < timeout) {
    await new Promise(r => setTimeout(r, 2000))
    elapsed += 2
    if (!existsSync(INBOX_DIR)) continue
    const after = (await readdir(INBOX_DIR)).filter(f => f.endsWith('.txt'))
    const newFiles = after.filter(f => !before.has(f))
    if (newFiles.length > 0) {
      for (const f of newFiles) {
        const content = readFileSync(join(INBOX_DIR, f), 'utf8')
        console.log('')
        console.log(chalk.green('  ✓ Result received') + chalk.dim(` (${f})`))
        console.log('')
        for (const line of content.trim().split('\n')) {
          console.log('  ' + chalk.dim(line.split(':')[0] + ':') + ' ' + line.split(':').slice(1).join(':').trim())
        }
        console.log('')
      }
      return
    }
  }

  console.log(chalk.yellow('\n  ~ Timed out waiting for result'))
}
