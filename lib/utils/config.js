import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'

export const CONFIG_DIR = join(homedir(), '.shellmates')
export const CONFIG_PATH = join(CONFIG_DIR, 'config.json')
export const INBOX_DIR = join(CONFIG_DIR, 'inbox')

const DEFAULTS = {
  permission_mode: 'default',
  orchestrator_permission_mode: 'default',
  default_agent: 'gemini',
  orchestrator: 'claude',
}

export function readConfig() {
  if (!existsSync(CONFIG_PATH)) return { ...DEFAULTS }
  try {
    const raw = readFileSync(CONFIG_PATH, 'utf8')
    return { ...DEFAULTS, ...JSON.parse(raw) }
  } catch {
    return { ...DEFAULTS }
  }
}

export function writeConfig(config) {
  mkdirSync(CONFIG_DIR, { recursive: true })
  // Strip internal _docs key before writing user-facing config
  const { _docs, ...clean } = config
  writeFileSync(CONFIG_PATH, JSON.stringify(clean, null, 2) + '\n')
}

export function ensureDirs() {
  mkdirSync(CONFIG_DIR, { recursive: true })
  mkdirSync(INBOX_DIR, { recursive: true })
}
