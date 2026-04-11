import chalk from 'chalk'
import { readdirSync, readFileSync, existsSync } from 'fs'
import { join } from 'path'
import { homedir } from 'os'
import { execSync } from 'child_process'
import { readConfig, INBOX_DIR } from '../utils/config.js'

export async function status() {
  const config = readConfig()

  console.log('')
  console.log(chalk.bold('  Shellmates — Status'))
  console.log(chalk.dim('  ────────────────────────────────────'))
  console.log('')

  // Config summary
  console.log(chalk.dim('  Config'))
  console.log('  ' + chalk.dim('permission_mode: ') + chalk.bold(config.permission_mode))
  console.log('  ' + chalk.dim('default_agent:   ') + chalk.bold(config.default_agent))
  console.log('  ' + chalk.dim('orchestrator:    ') + chalk.bold(config.orchestrator))
  console.log('')

  // Active tmux sessions
  let sessions = []
  try {
    const out = execSync('tmux list-sessions -F "#{session_name}"', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
    sessions = out.trim().split('\n').filter(Boolean)
  } catch {
    // tmux not running or no sessions
  }

  const shellmateSessions = sessions.filter(s => s.startsWith('shellmates'))
  console.log(chalk.dim('  Active sessions'))
  if (shellmateSessions.length === 0) {
    console.log('  ' + chalk.dim('none'))
  } else {
    for (const s of shellmateSessions) {
      console.log('  ' + chalk.green('●') + ' ' + s)
    }
  }
  console.log('')

  // Inbox files
  console.log(chalk.dim('  Inbox'))
  if (!existsSync(INBOX_DIR)) {
    console.log('  ' + chalk.dim('empty'))
  } else {
    const files = readdirSync(INBOX_DIR).filter(f => f.endsWith('.txt'))
    if (files.length === 0) {
      console.log('  ' + chalk.dim('empty'))
    } else {
      for (const f of files) {
        try {
          const content = readFileSync(join(INBOX_DIR, f), 'utf8')
          const statusLine = content.split('\n').find(l => l.startsWith('STATUS:'))
          const resultLine = content.split('\n').find(l => l.startsWith('RESULT:'))
          const statusVal = statusLine?.split(':')[1]?.trim() || '?'
          const resultVal = resultLine?.split(':').slice(1).join(':').trim() || ''
          const icon = statusVal === 'complete' ? chalk.green('✓') : chalk.yellow('~')
          console.log('  ' + icon + ' ' + chalk.dim(f))
          if (resultVal) console.log('    ' + chalk.dim(resultVal.split('\n')[0]))
        } catch {
          console.log('  ' + chalk.dim(f))
        }
      }
    }
  }
  console.log('')
}
