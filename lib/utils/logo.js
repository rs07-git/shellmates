import chalk from 'chalk'

// Pixel grid definitions — 1 = filled block, 0 = empty
// Each pixel renders as '██' (2 chars wide), giving correct letter proportions

const S = [
  [0,1,1,1,0],
  [1,0,0,0,0],
  [1,0,0,0,0],
  [0,1,1,1,0],
  [0,0,0,0,1],
  [0,0,0,0,1],
  [0,1,1,1,0],
]

const M = [
  [1,0,0,0,1],
  [1,1,0,1,1],
  [1,0,1,0,1],
  [1,0,0,0,1],
  [1,0,0,0,1],
  [1,0,0,0,1],
  [1,0,0,0,1],
]

const GAP = [[0],[0],[0],[0],[0],[0],[0]] // 1-pixel column gap between S and M

const FILLED  = chalk.hex('#4FC3F7')('██')
const EMPTY   = '  '

function renderGlyph(version) {
  const rows = S.map((sRow, i) => {
    const mRow = M[i]
    return [...sRow, 0, 0, ...mRow].map(p => p ? FILLED : EMPTY).join('')
  })

  const pad = '    '
  const lines = []
  lines.push('')
  for (const row of rows) {
    lines.push(pad + row)
  }
  lines.push('')
  lines.push(pad + chalk.hex('#4FC3F7').bold('shellmates') + (version ? chalk.dim(` v${version}`) : ''))
  lines.push(pad + chalk.dim('tmux multi-agent orchestration'))
  lines.push('')
  return lines.join('\n')
}

export function printLogo(version) {
  console.log(renderGlyph(version))
}
