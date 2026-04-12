import chalk from 'chalk'
import { existsSync, readFileSync, writeFileSync, mkdirSync, copyFileSync, chmodSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { homedir } from 'os'

const __dirname = dirname(fileURLToPath(import.meta.url))
const TEMPLATES_DIR = join(__dirname, '..', '..', 'templates', 'hooks')

const CLAUDE_DIR = join(homedir(), '.claude')
const HOOKS_DIR = join(CLAUDE_DIR, 'hooks')
const SETTINGS_PATH = join(CLAUDE_DIR, 'settings.json')
const HOOK_SCRIPT = join(HOOKS_DIR, 'shellmates-notify.sh')

const HOOK_ENTRY = {
  matcher: 'Bash',
  hooks: [
    {
      type: 'command',
      command: '~/.claude/hooks/shellmates-notify.sh',
      async: true,
      asyncRewake: true,
    },
  ],
}

export async function installHook({ force = false } = {}) {
  console.log('')
  console.log(chalk.bold('  Shellmates — Install Claude Code Hook'))
  console.log(chalk.dim('  ─────────────────────────────────────────'))
  console.log('')
  console.log(chalk.dim('  This installs a PostToolUse hook that notifies Claude natively'))
  console.log(chalk.dim('  when a shellmates agent finishes — no polling needed.'))
  console.log('')

  // 1. Copy hook script
  mkdirSync(HOOKS_DIR, { recursive: true })
  if (existsSync(HOOK_SCRIPT) && !force) {
    console.log(chalk.yellow('  ~') + ` Hook script already exists (use --force to overwrite)`)
  } else {
    copyFileSync(join(TEMPLATES_DIR, 'shellmates-notify.sh'), HOOK_SCRIPT)
    chmodSync(HOOK_SCRIPT, 0o755)
    console.log(chalk.green('  ✓') + ` Hook script installed: ~/.claude/hooks/shellmates-notify.sh`)
  }

  // 2. Merge hook entry into settings.json
  let settings = {}
  if (existsSync(SETTINGS_PATH)) {
    try {
      settings = JSON.parse(readFileSync(SETTINGS_PATH, 'utf8'))
    } catch {
      console.log(chalk.yellow('  ~') + ` Could not parse ${SETTINGS_PATH} — will create fresh`)
    }
  }

  // Check if our hook is already there
  const postToolUse = settings?.hooks?.PostToolUse || []
  const alreadyInstalled = postToolUse.some(
    entry => entry.hooks?.some(h => h.command?.includes('shellmates-notify'))
  )

  if (alreadyInstalled && !force) {
    console.log(chalk.yellow('  ~') + ` Hook entry already in settings.json (use --force to re-add)`)
  } else {
    if (!settings.hooks) settings.hooks = {}
    if (!settings.hooks.PostToolUse) settings.hooks.PostToolUse = []
    // Remove old shellmates entry if force
    if (force) {
      settings.hooks.PostToolUse = settings.hooks.PostToolUse.filter(
        e => !e.hooks?.some(h => h.command?.includes('shellmates-notify'))
      )
    }
    settings.hooks.PostToolUse.push(HOOK_ENTRY)
    writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2) + '\n')
    console.log(chalk.green('  ✓') + ` Hook entry added to ~/.claude/settings.json`)
  }

  console.log('')
  console.log(chalk.bold('  Done.'))
  console.log('')
  console.log('  After your next ' + chalk.dim('shellmates spawn') + ', Claude will be notified')
  console.log('  automatically when the agent finishes — no polling.')
  console.log('')
}
