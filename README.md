# mkspread

A terminal spreadsheet for people who know the classic DOS spreadsheets:
same screen layout, same `/` menu, same keystrokes.  Reads and writes
`.WK1` / `.WKS` files (planned).  GPL-3.0-or-later.

Status: **phase 4**: formulas.  Working now: data entry and EDIT mode, all
cell formats, formulas (operators, comparisons, `#AND#`/`#OR#`/`#NOT#`, string
concatenation, cell and range references, `@SUM` and a few constants),
recalculation in natural, columnwise or rowwise order with iteration count,
automatic or manual (F9) recalculation, circular-reference detection, range
selection in POINT mode, `/Worksheet Global`, `/Worksheet Column`,
`/Worksheet Erase`, `/Range Format`, `/Range Label`, `/Range Erase`, and
single-level Undo (a change journal).  Every other menu command is still a
stub.  Behaviour that has not been verified against real files is listed in
`docs/compat-notes.md`.

    make          build to build/mkspread
    make demo     run with a sample sheet
    make test     unit tests + end-to-end screen tests
    ./build/mkspread --help

Layout: `src/` source units (UI-free core: `sheet`, `cellfmt`, `menutree`,
`dates`, `formula`, `calc`, `u8edit`, `menudata`, `keys`, `session`, `commands`, `cmdsheet`,
`controller`; terminal side:
`ncw`, `terminal`, `view`, `keytest`), `tests/`, `docs/`, `build/` (output).
See `docs/keys.md` for key mapping.
