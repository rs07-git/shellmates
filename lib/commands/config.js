import chalk from 'chalk'
import inquirer from 'inquirer'
import { readConfig, writeConfig, ensureDirs } from '../utils/config.js'
import { AGENTS } from '../utils/agents.js'

const AGENT_CHOICES = Object.entries(AGENTS).map(([value, a]) => ({
  name: `${a.label.padEnd(14)} ${chalk.dim(a.hint)}`,
  value,
}))

const ORCHESTRATOR_CHOICES = [
  { name: `Claude Code   ${chalk.dim('(this session)')}`, value: 'claude' },
  { name: `Gemini CLI    ${chalk.dim('gemini')}`, value: 'gemini' },
  { name: `Codex CLI     ${chalk.dim('codex')}`, value: 'codex' },
]

export async function config() {
  ensureDirs()
  const current = readConfig()

  // Migrate old single-string format → array
  const currentAgents = current.default_agents
    || (current.default_agent ? [current.default_agent] : ['gemini'])

  console.log('')
  console.log(chalk.bold('  Shellmates — Settings'))
  console.log(chalk.dim('  ─────────────────────────────────────'))
  console.log('')

  const answers = await inquirer.prompt([
    {
      type: 'checkbox',
      name: 'default_agents',
      message: 'Default worker agent(s):',
      choices: AGENT_CHOICES,
      default: currentAgents,
      validate: (ans) => ans.length > 0 || 'Select at least one agent.',
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
          name: `default  ${chalk.dim('— agents ask before modifying files or running commands')}`,
          value: 'default',
        },
        {
          name: `bypass   ${chalk.dim('— agents run fully autonomously (gemini --yolo, codex --full-auto)')}`,
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
    {
      type: 'list',
      name: 'orchestrator_permission_mode',
      message: 'Orchestrator permission mode:',
      choices: [
        {
          name: `default  ${chalk.dim('— orchestrator asks before modifying files or running commands')}`,
          value: 'default',
        },
        {
          name: `bypass   ${chalk.dim('— orchestrator runs fully autonomously (--dangerously-skip-permissions, --yolo, --full-auto)')}`,
          value: 'bypass',
        },
      ],
      default: current.orchestrator_permission_mode || 'default',
      prefix: ' ',
    },
    {
      type: 'confirm',
      name: 'orch_bypass_confirmed',
      message: chalk.yellow('Orchestrator bypass lets the dispatching AI run without any permission prompts. Are you sure?'),
      default: false,
      prefix: ' ',
      when: (ans) => ans.orchestrator_permission_mode === 'bypass' && (current.orchestrator_permission_mode || 'default') !== 'bypass',
    },
  ])

  if (answers.permission_mode === 'bypass' && answers.bypass_confirmed === false) {
    answers.permission_mode = 'default'
    console.log('')
    console.log(chalk.dim('  Permission mode kept as: default'))
  }

  if (answers.orchestrator_permission_mode === 'bypass' && answers.orch_bypass_confirmed === false) {
    answers.orchestrator_permission_mode = 'default'
    console.log('')
    console.log(chalk.dim('  Orchestrator permission mode kept as: default'))
  }

  const { bypass_confirmed, orch_bypass_confirmed, ...toSave } = answers
  writeConfig(toSave)

  console.log('')
  console.log(chalk.green('  ✓') + ' Settings saved.')
  console.log('')
  console.log(chalk.dim('  default_agents:              ') + chalk.bold(toSave.default_agents.join(', ')))
  console.log(chalk.dim('  orchestrator:                ') + chalk.bold(toSave.orchestrator))
  console.log(chalk.dim('  permission_mode:             ') + chalk.bold(toSave.permission_mode))
  console.log(chalk.dim('  orchestrator_permission_mode:') + ' ' + chalk.bold(toSave.orchestrator_permission_mode))
  console.log('')
}
