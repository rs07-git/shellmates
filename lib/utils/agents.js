import { execSync, spawnSync } from 'child_process'
import chalk from 'chalk'

export const AGENTS = {
  gemini: {
    label: 'Gemini CLI',
    bin: 'gemini',
    pkg: '@google/gemini-cli',
    hint: 'google/gemini-cli',
  },
  codex: {
    label: 'Codex CLI',
    bin: 'codex',
    pkg: '@openai/codex',
    hint: 'openai/codex',
  },
  claude: {
    label: 'Claude Code',
    bin: 'claude',
    pkg: '@anthropic-ai/claude-code',
    hint: 'anthropic-ai/claude-code',
  },
}

/** Returns { gemini: true, codex: false, claude: true } */
export function detectAgents() {
  const results = {}
  for (const [key, agent] of Object.entries(AGENTS)) {
    try {
      execSync(`which ${agent.bin}`, { stdio: 'ignore' })
      results[key] = true
    } catch {
      results[key] = false
    }
  }
  return results
}

/** Print detection results and offer to install missing agents. */
export async function checkAndInstallAgents() {
  const { default: inquirer } = await import('inquirer')
  const detected = detectAgents()
  const missing = Object.entries(detected).filter(([, ok]) => !ok).map(([k]) => k)

  console.log('  Checking agents...')
  for (const [key, ok] of Object.entries(detected)) {
    const a = AGENTS[key]
    if (ok) {
      console.log(chalk.green('  ✓') + ` ${a.label.padEnd(14)} ${chalk.dim(a.hint)}`)
    } else {
      console.log(chalk.red('  ✗') + ` ${a.label.padEnd(14)} ${chalk.dim('not found')}`)
    }
  }

  if (missing.length === 0) return

  console.log('')
  const { toInstall } = await inquirer.prompt([
    {
      type: 'checkbox',
      name: 'toInstall',
      message: 'Install missing agents?',
      choices: missing.map(k => ({
        name: `${AGENTS[k].label}  ${chalk.dim(AGENTS[k].hint)}`,
        value: k,
        checked: true,
      })),
      prefix: ' ',
    },
  ])

  if (toInstall.length === 0) return

  console.log('')
  for (const key of toInstall) {
    const a = AGENTS[key]
    console.log(chalk.dim(`  Installing ${a.label}...`))
    const result = spawnSync('npm', ['install', '-g', `${a.pkg}@latest`], {
      stdio: 'inherit',
      shell: true,
    })
    if (result.status === 0) {
      console.log(chalk.green('  ✓') + ` ${a.label} installed`)
    } else {
      console.log(chalk.yellow('  ~') + ` ${a.label} install failed — try: ${chalk.dim(`npm install -g ${a.pkg}@latest`)}`)
    }
  }
}
