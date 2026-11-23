# mkspread

A terminal spreadsheet for people who know the classic DOS spreadsheets:
same screen layout, same `/` menu, same keystrokes.  Reads and writes
`.WK1` / `.WKS` files (planned).  GPL-3.0-or-later.

Status: **phase 9**: the `/Data` commands.  Working now: everything from
phase 8 (formulas and the `@function` library, editing commands, range names,
titles, worksheet files, macros with recording and step mode) plus `/Data`
Fill, Table 1 and 2, Sort, Query (Find, Extract, Unique, Delete),
Distribution, Matrix, Regression and Parse (see `docs/data.md`).  Not yet:
`/Worksheet Window`, `/Print`, help screens, recovery/autosave, `.XLS`.  Every
other menu command is still a stub.  Behaviour not yet verified is listed in
`docs/compat-notes.md`; sources are in `docs/SOURCES.md`.

To check the engine against the original program, `make testsheet` writes
`private-samples/MKTEST.WK1`: open it in 1-2-3, recalculate, and read the
number of differences in A3.

`make macrosheet` writes `private-samples/MACROS.WK1` the same way for the macro
interpreter: press Alt-R in 1-2-3 and read the differences in A3.

The file layer is tested against real files: if a `private-samples/` folder
(git-ignored) holds `.WK1` files, `make test` loads each one, checks every
formula re-encodes byte for byte and recalculates to the stored value, and
round-trips the file.

    make          build to build/mkspread
    make demo     run with a sample sheet
    make test     unit tests + end-to-end screen tests
    ./build/mkspread --help

Layout: `src/` source units (UI-free core: `sheet`, `cellfmt`, `menutree`,
`dates`, `formula`, `calc`, `editops`, `charsets`, `wk1`, `textimport`, `macro`, `dataops`, `cmddata`, `funclib` (with `fn_core`, `fn_time`, `fn_fin`), `u8edit`, `menudata`, `keys`, `session`, `commands`, `cmdsheet`, `cmdedit`, `cmdfile`,
`controller`; terminal side:
`ncw`, `terminal`, `view`, `keytest`), `tests/`, `docs/`, `build/` (output).
See `docs/keys.md` for key mapping.
