import chalk from 'chalk'
import { spawnSync } from 'child_process'

export async function update() {
  console.log('')
  console.log(chalk.bold('  Shellmates — Update'))
  console.log(chalk.dim('  ─────────────────────────────────────'))
  console.log('')
  console.log(chalk.dim('  Running: npm install -g shellmates@latest'))
  console.log('')

  const result = spawnSync('npm', ['install', '-g', 'shellmates@latest'], {
    stdio: 'inherit',
  })

  if (result.status === 0) {
    console.log('')
    console.log(chalk.green('  ✓') + ' Updated. Run ' + chalk.bold('shellmates') + ' to see the new version.')
    console.log('')
  } else {
    console.log('')
    console.log(chalk.red('  ✗') + ' Update failed.')
    console.log(chalk.dim('    Try manually: npm install -g shellmates@latest'))
    console.log('')
    process.exit(1)
  }
}
