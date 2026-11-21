# mkspread

A terminal spreadsheet for people who know the classic DOS spreadsheets:
same screen layout, same `/` menu, same keystrokes.  Reads and writes
`.WK1` / `.WKS` files (planned).  GPL-3.0-or-later.

Status: **phase 5**: editing commands.  Working now: everything from phase 4
(data entry, EDIT mode, cell formats, formulas and recalculation, Undo) plus
`/Copy`, `/Move`, `/Range Value`, `/Range Trans`, `/Worksheet Insert` and
`Delete` for rows and columns (all references, range names, column widths and
titles follow), range names (`/Range Name` Create, Delete, Labels, Reset,
Table; usable in formulas and range prompts; F3 lists them) and
`/Worksheet Titles`.  Not yet: `/Worksheet Window`, files, macros, `@`
functions beyond `@SUM`, printing, data commands.  Every other menu command is
still a stub.  Behaviour not yet verified against real files is listed in
`docs/compat-notes.md`.

    make          build to build/mkspread
    make demo     run with a sample sheet
    make test     unit tests + end-to-end screen tests
    ./build/mkspread --help

Layout: `src/` source units (UI-free core: `sheet`, `cellfmt`, `menutree`,
`dates`, `formula`, `calc`, `editops`, `u8edit`, `menudata`, `keys`, `session`, `commands`, `cmdsheet`, `cmdedit`,
`controller`; terminal side:
`ncw`, `terminal`, `view`, `keytest`), `tests/`, `docs/`, `build/` (output).
See `docs/keys.md` for key mapping.
