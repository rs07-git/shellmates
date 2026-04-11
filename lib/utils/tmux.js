import { execSync, spawnSync } from 'child_process'
import { readdirSync, existsSync } from 'fs'

export function tmuxAvailable() {
  try {
    execSync('which tmux', { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}

export function listSessions() {
  try {
    const out = execSync('tmux list-sessions -F "#{session_name}"', { encoding: 'utf8' })
    return out.trim().split('\n').filter(Boolean)
  } catch {
    return []
  }
}

export function sessionExists(name) {
  return listSessions().includes(name)
}

export function listInboxFiles(inboxDir) {
  if (!existsSync(inboxDir)) return []
  return readdirSync(inboxDir).filter(f => f.endsWith('.txt'))
}

export function killSession(name) {
  try {
    execSync(`tmux kill-session -t ${name}`, { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}

export function runScript(scriptPath, args = [], { inherit = true } = {}) {
  const result = spawnSync('bash', [scriptPath, ...args], {
    stdio: inherit ? 'inherit' : 'pipe',
    encoding: 'utf8',
  })
  return result
}
