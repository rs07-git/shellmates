import chalk from 'chalk'
import inquirer from 'inquirer'
import { readConfig, writeConfig, ensureDirs } from '../utils/config.js'

const AGENT_CHOICES = [
  { name: 'Gemini CLI  (google/gemini-cli)', value: 'gemini' },
  { name: 'Codex CLI   (openai/codex)', value: 'codex' },
  { name: 'Ask me each time', value: 'ask' },
]

const ORCHESTRATOR_CHOICES = [
  { name: 'Claude Code  (this session)', value: 'claude' },
  { name: 'Gemini CLI', value: 'gemini' },
  { name: 'Codex CLI', value: 'codex' },
]

export async function config() {
  ensureDirs()
  const current = readConfig()

  console.log('')
  console.log(chalk.bold('  Shellmates — Settings'))
  console.log(chalk.dim('  ────────────────────────────────────'))
  console.log(chalk.dim(`  Current config: ~/.shellmates/config.json`))
  console.log('')

  const answers = await inquirer.prompt([
    {
      type: 'list',
      name: 'default_agent',
      message: 'Default worker agent:',
      choices: AGENT_CHOICES,
      default: current.default_agent,
      prefix: ' ',
    },
    {
      type: 'list',
      name: 'orchestrator',
      message: 'Orchestrator (who dispatches tasks):',
      choices: ORCHESTRATOR_CHOICES,
      default: current.orchestrator,
      prefix: ' ',
    },
    {
      type: 'list',
      name: 'permission_mode',
      message: 'Permission mode:',
      choices: [
        {
          name: 'default  — agents ask before modifying files or running commands',
          value: 'default',
        },
        {
          name: 'bypass   — agents run fully autonomously (gemini --yolo, codex --full-auto)',
          value: 'bypass',
        },
      ],
      default: current.permission_mode,
      prefix: ' ',
    },
    {
      type: 'confirm',
      name: 'bypass_confirmed',
      message: chalk.yellow('Bypass mode lets agents modify files without asking. Are you sure?'),
      default: false,
      prefix: ' ',
      when: (ans) => ans.permission_mode === 'bypass' && current.permission_mode !== 'bypass',
    },
  ])

  // If user chose bypass but didn't confirm, revert to default
  if (answers.permission_mode === 'bypass' && answers.bypass_confirmed === false) {
    answers.permission_mode = 'default'
    console.log('')
    console.log(chalk.dim('  Permission mode kept as: default'))
  }

  const { bypass_confirmed, ...toSave } = answers
  writeConfig(toSave)

  console.log('')
  console.log(chalk.green('  ✓') + ' Settings saved.')
  console.log('')
  console.log(chalk.dim('  permission_mode: ') + chalk.bold(toSave.permission_mode))
  console.log(chalk.dim('  default_agent:   ') + chalk.bold(toSave.default_agent))
  console.log(chalk.dim('  orchestrator:    ') + chalk.bold(toSave.orchestrator))
  console.log('')
}
