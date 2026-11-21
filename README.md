# mkspread

A terminal spreadsheet for people who know the classic DOS spreadsheets:
same screen layout, same `/` menu, same keystrokes.  Reads and writes
`.WK1` / `.WKS` files (planned).  GPL-3.0-or-later.

Status: **phase 3**: data entry and worksheet basics.  Working now:
data entry, EDIT mode (F2), all cell formats (Fixed, Sci, Currency, Comma,
General, +/-, Percent, Date/Time, Text, Hidden), `/Worksheet Global` Format,
Label-Prefix, Column-Width and Zero, `/Worksheet Column`, `/Worksheet Erase`,
`/Range Format`, `/Range Label`, `/Range Erase`, range selection in POINT mode,
and single-level Undo (Alt-F4 or Ctrl-U, recorded as a change journal).  Every other menu command is still a
stub, and formulas are stored but not yet calculated.

    make          build to build/mkspread
    make demo     run with a sample sheet
    make test     unit tests + end-to-end screen tests
    ./build/mkspread --help

Layout: `src/` source units (UI-free core: `sheet`, `cellfmt`, `menutree`,
`dates`, `u8edit`, `menudata`, `keys`, `session`, `commands`, `cmdsheet`,
`controller`; terminal side:
`ncw`, `terminal`, `view`, `keytest`), `tests/`, `docs/`, `build/` (output).
See `docs/keys.md` for key mapping.
