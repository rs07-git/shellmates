#!/usr/bin/env node
import { program } from 'commander'
import { readFileSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const pkg = JSON.parse(readFileSync(join(__dirname, '..', 'package.json'), 'utf8'))

program
  .name('shellmates')
  .description('Seamless tmux multi-agent orchestration')
  .version(pkg.version)

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
  .description('Dispatch a task to a worker agent in a new tmux session')
  .option('-t, --task <text>', 'Inline task text to dispatch')
  .option('-f, --task-file <path>', 'Path to a file containing the task')
  .option('-a, --agent <name>', 'Override agent for this task (gemini|codex)')
  .option('-s, --session <name>', 'tmux session name (default: shellmates-<ts>)')
  .option('-p, --project <path>', 'Project directory for the worker (default: cwd)')
  .option('-w, --watch', 'Wait and print result when the agent finishes')
  .option('--no-ping', 'Skip background inbox watcher')
  .action(async (opts) => {
    const { spawn } = await import('../lib/commands/spawn.js')
    await spawn({
      task: opts.task,
      taskFile: opts.taskFile,
      agent: opts.agent,
      session: opts.session,
      project: opts.project,
      watch: opts.watch,
      noPing: !opts.ping,
    })
  })

// ── shellmates status ────────────────────────────────────────────────────────
program
  .command('status')
  .description('Show active sessions, config, and inbox results')
  .action(async () => {
    const { status } = await import('../lib/commands/status.js')
    await status()
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
