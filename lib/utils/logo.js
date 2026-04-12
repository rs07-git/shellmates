import chalk from 'chalk'

// Pixel grid definitions — 1 = filled block, 0 = empty
// 3 pixels wide × 5 pixels tall per letter (compact, fits 80-char terminals)
// Each pixel renders as '██' (2 chars), gap between letters = '  ' (1 empty pixel)

const LETTERS = {
  S: [
    [1,1,1],
    [1,0,0],
    [1,1,1],
    [0,0,1],
    [1,1,1],
  ],
  H: [
    [1,0,1],
    [1,0,1],
    [1,1,1],
    [1,0,1],
    [1,0,1],
  ],
  E: [
    [1,1,1],
    [1,0,0],
    [1,1,0],
    [1,0,0],
    [1,1,1],
  ],
  L: [
    [1,0,0],
    [1,0,0],
    [1,0,0],
    [1,0,0],
    [1,1,1],
  ],
  M: [
    [1,0,1],
    [1,1,1],
    [1,0,1],
    [1,0,1],
    [1,0,1],
  ],
  A: [
    [0,1,0],
    [1,0,1],
    [1,1,1],
    [1,0,1],
    [1,0,1],
  ],
  T: [
    [1,1,1],
    [0,1,0],
    [0,1,0],
    [0,1,0],
    [0,1,0],
  ],
}

// SHELLMATES = S H E L L M A T E S
const WORD = ['S','H','E','L','L','M','A','T','E','S']

const FILLED = chalk.white('██')
const EMPTY  = '  '

export function printLogo(version) {
  const numRows = 5
  const rows = Array.from({ length: numRows }, (_, rowIdx) => {
    return WORD.map(ch => {
      const grid = LETTERS[ch]
      return grid[rowIdx].map(p => p ? FILLED : EMPTY).join('')
    }).join(EMPTY) // 1-pixel gap between letters
  })

  const pad = '  '
  console.log('')
  for (const row of rows) {
    console.log(pad + row)
  }
  console.log('')
  if (version) {
    console.log(pad + chalk.dim(`v${version}  ·  tmux multi-agent orchestration`))
  }
  console.log('')
}
