import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs'
import { join } from 'path'
import { homedir } from 'os'

const CACHE_PATH = join(homedir(), '.shellmates', 'update-cache.json')
const TTL_MS = 24 * 60 * 60 * 1000 // 24 hours

export async function checkUpdate(currentVersion) {
  // Try cache first
  let latestVersion = null
  if (existsSync(CACHE_PATH)) {
    try {
      const cache = JSON.parse(readFileSync(CACHE_PATH, 'utf8'))
      if (Date.now() - cache.checkedAt < TTL_MS) {
        latestVersion = cache.latest
      }
    } catch {}
  }

  if (!latestVersion) {
    try {
      const res = await fetch('https://registry.npmjs.org/shellmates/latest', {
        signal: AbortSignal.timeout(3000),
      })
      const data = await res.json()
      latestVersion = data.version
      try {
        mkdirSync(join(homedir(), '.shellmates'), { recursive: true })
        writeFileSync(CACHE_PATH, JSON.stringify({ latest: latestVersion, checkedAt: Date.now() }))
      } catch {}
    } catch {
      return null // network error or timeout — silent
    }
  }

  if (!latestVersion || !isNewer(latestVersion, currentVersion)) return null
  return { current: currentVersion, latest: latestVersion }
}

function isNewer(a, b) {
  const p = v => v.replace(/[^0-9.]/g, '').split('.').map(Number)
  const [aM, am, ap] = p(a)
  const [bM, bm, bp] = p(b)
  if (aM !== bM) return aM > bM
  if (am !== bm) return am > bm
  return ap > bp
}
