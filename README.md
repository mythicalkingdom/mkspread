# mkspread

A terminal spreadsheet for people who know the classic DOS spreadsheets:
same screen layout, same `/` menu, same keystrokes.  Reads and writes
`.WK1` / `.WKS` files (planned).  GPL-3.0-or-later.

Status: **phase 6**: files.  Working now: everything from phase 5 plus
worksheet files.  `mkspread file.wk1` opens a file; `/File Retrieve`, `Save`
(`.WK1`, or `.WKS` for the original format), `Combine`, `Xtract`, `Erase`,
`List`, `Import` (text lines, numbers, CSV) and `Directory` work, with F3
listing files in any file-name prompt.  Labels are stored in LICS and shown as
UTF-8.  Not yet: `/Worksheet Window`, macros, `@` functions beyond `@SUM`,
`@ROUND`, `@PMT` and a few constants, printing, data commands, `.XLS`.  Every
other menu command is still a stub.  Behaviour not yet verified is listed in
`docs/compat-notes.md`; the sources used are in `docs/SOURCES.md`.

The file layer is tested against real files: if a `private-samples/` folder
(git-ignored) holds `.WK1` files, `make test` loads each one, checks every
formula re-encodes byte for byte and recalculates to the stored value, and
round-trips the file.

    make          build to build/mkspread
    make demo     run with a sample sheet
    make test     unit tests + end-to-end screen tests
    ./build/mkspread --help

Layout: `src/` source units (UI-free core: `sheet`, `cellfmt`, `menutree`,
`dates`, `formula`, `calc`, `editops`, `charsets`, `wk1`, `textimport`, `u8edit`, `menudata`, `keys`, `session`, `commands`, `cmdsheet`, `cmdedit`, `cmdfile`,
`controller`; terminal side:
`ncw`, `terminal`, `view`, `keytest`), `tests/`, `docs/`, `build/` (output).
See `docs/keys.md` for key mapping.
