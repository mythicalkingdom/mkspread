# Configuration, autosave and recovery

## Configuration file
`~/.config/mkspread/mkspread.conf` (or under `$XDG_CONFIG_HOME`).  Lines of
`key = value`; `#` starts a comment.  Problems are reported on the terminal at start-up.

| Key | Meaning | Default |
|---|---|---|
| `autosave` | save the worksheet to its file every N minutes when it has changed (0 = off) | 0 |
| `recovery` | write the recovery copy every N seconds when there are changes (0 = off) | 30 |
| `expand` | use the whole terminal instead of 80x25 | no |

`--autosave=N` and `--expand` on the command line override the file.

`/Worksheet Global Default` changes the settings below while the program runs;
**Update** writes them all to this file (comments are not kept).  **Status** lists them.

| Key | Meaning | Default |
|---|---|---|
| `directory` | folder to start in | (where started) |
| `print-left`, `print-right`, `print-top`, `print-bottom`, `print-length` | printer margins and page length | 4, 76, 2, 2, 66 |
| `print-setup` | printer setup string (`\015` is decimal code 15) | empty |
| `print-name` | CUPS queue for `lp -d` | system default |
| `print-interface`, `print-autolf`, `print-wait` | kept for compatibility | 1, no, no |
| `punctuation` | `A`..`H`: decimal, thousands and argument separators (A `. , ,`; B `, . .`; C `. space ,`; D `, space .`; E `. , ;`; F `, . ;`; G `. space ;`; H `, space ;`) | A |
| `currency`, `currency-position` | currency symbol (up to 4 characters), `prefix` or `suffix` | `$`, prefix |
| `negative` | `parentheses` or `sign` for negative Currency and Comma numbers | parentheses |
| `date-format`, `time-format` | `A`..`D`: international formats of D4/D5 and D8/D9 (date A MM/DD/YY, B DD/MM/YY, C DD.MM.YY, D YY-MM-DD; time A HH:MM:SS, B HH.MM.SS, C HH,MM,SS, D HHhMMmSSs) | A, A |
| `clock` | `standard`, `international` or `none` | standard |
| `undo`, `beep`, `help` | Undo on/off; beep and help source kept for compatibility | yes, yes, instant |

Numbers are still typed with a decimal point; the punctuation only changes how
they are shown.

## Punctuation in typed numbers and text files
With a Punctuation other than A (for example B, a comma as the decimal point), numbers
and formulas are **typed** in that punctuation: `1,5`, and `@ROUND(A1.2)` where the point
separates arguments (E to H use a semicolon).  They are shown that way when edited (F2)
and on the status line.  Inside the program and in `.WK1` files they are stored with a
decimal point and commas, so files are the same everywhere.  A range is always `A1..B2`.
Text import (`/File Import Numbers`, CSV) and `/Data Parse` read the decimal separator
of the chosen punctuation, and with a decimal comma the fields of a `.CSV` file are
separated by semicolons.

## Quitting
`/Quit Yes` asks once more when the worksheet has changes that are not in a file.

## Autosave
With `autosave` above 0, a worksheet that has a file name and unsaved changes is
saved to that file at the interval (the screen says `Autosaved NAME`).  A worksheet
without a name is only covered by the recovery copy.

## Recovery
While there are unsaved changes a copy is kept in
`$XDG_STATE_HOME/mkspread/recover` (default `~/.local/state/mkspread/recover`) as
`<pid>.wk1` plus `<pid>.txt` (the original file name and the time).  A normal exit
removes them.  A crash, `kill` or a dropped SSH connection leaves them (a hangup
or TERM first writes a last copy).  The next start asks: **Recover** loads the copy
(saving then goes to the original file), **Discard** deletes it, **Later** keeps it.
