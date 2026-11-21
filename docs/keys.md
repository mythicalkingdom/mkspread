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
| Alt-letter | macro key | sent as Esc + letter; works over SSH |
| Alt-F4 | Undo | Alternative: **Ctrl-U** (many terminals swallow Alt-F4) |
| Ctrl-C | Break (leave menu or entry) | |
| `/` or `<` | open the menu | |

Plain Esc is told apart from Alt-letter by timing: a letter arriving right
after Esc is Alt-letter.  On very slow links, type Esc then wait briefly.
