#!/usr/bin/env node
import { program } from 'commander'
import { readFileSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const pkg = JSON.parse(readFileSync(join(__dirname, '..', 'package.json'), 'utf8'))

// ── Bare call or top-level --help/-h → custom welcome screen ─────────────────
const args = process.argv.slice(2)
const isWelcome = args.length === 0 || args[0] === '--help' || args[0] === '-h' || args[0] === 'help'

if (isWelcome) {
  const chalk = (await import('chalk')).default
  const { printLogo } = await import('../lib/utils/logo.js')
  const { checkUpdate } = await import('../lib/utils/update-check.js')
  const { existsSync } = await import('fs')
  const { join: pathJoin } = await import('path')
  const { homedir } = await import('os')

  printLogo(pkg.version)

  const cmd = (name, desc) =>
    `  ${chalk.bold(name.padEnd(16))}${chalk.dim(desc)}`

  console.log(chalk.dim('  COMMANDS'))
  console.log(cmd('spawn',         'Start a session — Claude asks what you want to work on'))
  console.log(cmd('init',          'First-time setup — create config and directories'))
  console.log(cmd('config',        'Configure agents, orchestrator, and permission mode'))
  console.log(cmd('status',        'Show active sessions and inbox results'))
  console.log(cmd('install-hook',  'Wire up native Claude Code AGENT_PING notifications'))
  console.log(cmd('teardown',      'Kill shellmates tmux sessions'))
  console.log(cmd('update',        'Update shellmates to the latest version'))
  console.log('')
  console.log(chalk.dim('  EXAMPLES'))
  console.log(`  ${chalk.dim('shellmates spawn')}                          ${chalk.dim('# natural-language intake with Claude')}`)
  console.log(`  ${chalk.dim('shellmates spawn --task "Add dark mode"')}   ${chalk.dim('# direct dispatch to default agent')}`)
  console.log(`  ${chalk.dim('shellmates status')}`)
  console.log('')
  console.log('  ' + chalk.dim('shellmates <command> --help') + chalk.dim(' for command details.'))
  console.log('')

  // First-run nudge
  const configPath = pathJoin(homedir(), '.shellmates', 'config.json')
  if (!existsSync(configPath)) {
    console.log(chalk.yellow('  ~ Not set up yet.') + '  Run ' + chalk.bold('shellmates init') + ' to get started.')
    console.log('')
  }

  // Update notice (non-blocking, cached — won't slow you down)
  const update = await checkUpdate(pkg.version)
  if (update) {
    console.log(chalk.cyan(`  ✨ Update available: ${chalk.dim(update.current)} → ${chalk.bold(update.latest)}`))
    console.log(chalk.dim('     shellmates update'))
    console.log('')
  }

  process.exit(0)
}

program
  .name('shellmates')
  .description('Seamless tmux multi-agent orchestration')
  .version(pkg.version, '-v, --version', 'Print version number')

// ── shellmates init ──────────────────────────────────────────────────────────
program
  .command('init')
  .description('First-time setup — create config and directories')
  .option('--force', 'Reset config to defaults even if it already exists')
  .action(async (opts) => {
    const { init } = await import('../lib/commands/init.js')
    await init(opts)
  })

// ── shellmates config ────────────────────────────────────────────────────────
program
  .command('config')
  .description('Interactive settings — agent, permission mode, orchestrator')
  .action(async () => {
    const { config } = await import('../lib/commands/config.js')
    await config()
  })

// ── shellmates spawn ─────────────────────────────────────────────────────────
program
  .command('spawn')
  .description('Start a session — Claude interviews you and dispatches agents, or pass --task for direct dispatch')
  .option('-t, --task <text>', 'Direct task text (skips intake, dispatches immediately)')
  .option('-f, --task-file <path>', 'Path to a task file (skips intake, dispatches immediately)')
  .option('-a, --agent <name>', 'Override agent for direct dispatch (gemini|codex)')
  .option('-s, --session <name>', 'tmux session name')
  .option('-p, --project <path>', 'Project directory (default: cwd)')
  .option('-w, --watch', 'Wait and print result when agent finishes')
  .option('--no-ping', 'Skip background inbox watcher')
  .option('-r, --reuse-pane <paneId>', 'Reuse an existing warm agent pane (send /clear, skip startup)')
  .action(async (opts) => {
    // No task provided → open the orchestrator intake (pond mode)
    if (!opts.task && !opts.taskFile) {
      const { pond } = await import('../lib/commands/pond.js')
      await pond({ session: opts.session, project: opts.project })
      return
    }
    const { spawn } = await import('../lib/commands/spawn.js')
    await spawn({
      task: opts.task,
      taskFile: opts.taskFile,
      agent: opts.agent,
      session: opts.session,
      project: opts.project,
      watch: opts.watch,
      noPing: !opts.ping,
      reusePane: opts.reusePane,
    })
  })

// ── shellmates pond (alias for spawn with no task) ───────────────────────────
program
  .command('pond')
  .description('Start an orchestrator session — Claude asks what you want to work on')
  .option('-s, --session <name>', 'tmux session name')
  .option('-p, --project <path>', 'Project directory (default: cwd)')
  .action(async (opts) => {
    const { pond } = await import('../lib/commands/pond.js')
    await pond({ session: opts.session, project: opts.project })
  })

// ── shellmates status ────────────────────────────────────────────────────────
program
  .command('status')
  .description('Show active sessions, config, and inbox results')
  .action(async () => {
    const { status } = await import('../lib/commands/status.js')
    await status()
  })

// ── shellmates install-hook ──────────────────────────────────────────────────
program
  .command('install-hook')
  .description('Install Claude Code PostToolUse hook for native AGENT_PING notifications')
  .option('--force', 'Overwrite existing hook and re-add settings entry')
  .action(async (opts) => {
    const { installHook } = await import('../lib/commands/install-hook.js')
    await installHook(opts)
  })

// ── shellmates update ────────────────────────────────────────────────────────
program
  .command('update')
  .description('Update shellmates to the latest version')
  .action(async () => {
    const { update } = await import('../lib/commands/update.js')
    await update()
  })

// ── shellmates teardown ──────────────────────────────────────────────────────
program
  .command('teardown [session]')
  .description('Kill shellmates tmux sessions and clean up (default: all)')
  .action(async (session) => {
    const { execSync } = await import('child_process')
    const chalk = (await import('chalk')).default
    let sessions = []
    try {
      const out = execSync('tmux list-sessions -F "#{session_name}"', {
        encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']
      })
      sessions = out.trim().split('\n').filter(Boolean)
    } catch {}

    const targets = session
      ? sessions.filter(s => s === session)
      : sessions.filter(s => s.startsWith('shellmates'))

    if (targets.length === 0) {
      console.log(chalk.dim('\n  No shellmates sessions to tear down.\n'))
      return
    }

    for (const s of targets) {
      try {
        execSync(`tmux kill-session -t ${s}`, { stdio: 'ignore' })
        console.log(chalk.green('  ✓') + ` Killed session: ${s}`)
      } catch {
        console.log(chalk.red('  ✗') + ` Could not kill: ${s}`)
      }
    }
    console.log('')
  })

program.parse()
