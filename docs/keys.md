# Key mapping

Terminals cannot send every key a DOS keyboard could.  mkspread receives keys
through ncurses (so `TERM` and terminfo apply) plus an extra table of common
escape sequences in `src/keys.pas`.  Run `mkspread --keytest` to see exactly what
your terminal delivers.

| Key | Meaning | Notes |
|-----|---------|-------|
| Arrows, Home, End, PgUp, PgDn | cursor movement | |
| Ctrl-Right / Ctrl-Left | big move right / left | xterm, VTE, tmux, PuTTY. Alternatives: Tab / Shift-Tab |
| F1 .. F10 | HELP, EDIT, NAME, ABS, GOTO, WINDOW, QUERY, TABLE, CALC, GRAPH | |
| Alt-letter | run macro `\letter` | sent as Esc + letter; works over SSH |
| Alt-F3 | run a macro chosen from the range names | |
| Alt-F4 | Undo | Alternative: **Ctrl-U** (many terminals swallow Alt-F4) |
| Ctrl-C | Break (leave menu or entry) | |
| `/` or `<` | open the menu | |

Plain Esc is told apart from Alt-letter by timing: a letter arriving right
after Esc is Alt-letter.  On very slow links, type Esc then wait briefly.

## Editing keys

| Key | In mode | Meaning |
|-----|---------|---------|
| F2 | READY / LABEL / VALUE | edit the cell (or the entry) in EDIT mode |
| Left, Right, Home, End | EDIT | move within the text |
| Backspace, Del | EDIT | delete before / at the cursor |
| Enter, Up, Down | EDIT | accept (arrows also move) |
| Esc | EDIT / prompts | cancel |
| `.` | POINT | anchor the range at the pointer |
| Esc, Backspace | POINT | unanchor, then cancel |
| letters/digits | POINT | type a range such as `A1..C5` instead of pointing |
| Left, Right | column-width prompt | change the width and preview it |
| F3 | POINT mode, name prompts | list range names; Left/Right choose, Enter accepts |
| Alt-F2 | STEP mode on/off (macros run one key at a time) | |
| Alt-F5 | LEARN mode on/off (record keystrokes into the learn range) | |
| F8 | re-run the last /Data Table | |
