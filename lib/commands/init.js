import chalk from 'chalk'
import { existsSync } from 'fs'
import { CONFIG_PATH, CONFIG_DIR, INBOX_DIR, readConfig, writeConfig, ensureDirs } from '../utils/config.js'
import { tmuxAvailable } from '../utils/tmux.js'
import { printLogo } from '../utils/logo.js'

export async function init({ force = false } = {}) {
  const { readFileSync } = await import('fs')
  const { join, dirname, fileURLToPath } = await import('path')
  const { fileURLToPath: fu } = await import('url')
  let version = '0.1.0'
  try {
    const __dirname = dirname(fu(import.meta.url))
    const pkg = JSON.parse(readFileSync(join(__dirname, '..', '..', 'package.json'), 'utf8'))
    version = pkg.version
  } catch {}

  printLogo(version)
  console.log(chalk.dim('  ─────────────────────────────'))
  console.log('')

  // tmux check
  if (!tmuxAvailable()) {
    console.log(chalk.red('  ✗ tmux not found'))
    console.log(chalk.dim('    Install it: brew install tmux'))
    console.log('')
    process.exit(1)
  }
  console.log(chalk.green('  ✓') + ' tmux found')

  // Create dirs
  ensureDirs()
  console.log(chalk.green('  ✓') + ` ~/.shellmates/ ready`)
  console.log(chalk.green('  ✓') + ` ~/.shellmates/inbox/ ready`)

  // Config
  if (existsSync(CONFIG_PATH) && !force) {
    console.log(chalk.yellow('  ~') + ` Config already exists at ${CONFIG_PATH}`)
    console.log(chalk.dim('    Run with --force to reset, or use: shellmates config'))
  } else {
    writeConfig({
      permission_mode: 'default',
      default_agent: 'gemini',
      orchestrator: 'claude',
    })
    console.log(chalk.green('  ✓') + ` Config created at ${CONFIG_PATH}`)
  }

  console.log('')
  console.log(chalk.bold('  Ready.'))
  console.log('')
  console.log('  Next steps:')
  console.log(chalk.dim('    shellmates config') + '  — configure agents and permission mode')
  console.log(chalk.dim('    shellmates spawn') + '   — dispatch a task to a worker agent')
  console.log('')
}
