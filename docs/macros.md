# Macros

A macro is text in worksheet cells.  It is read from its first cell down until
a cell that is empty or not text (a label, or a formula that returns text).
Each character is typed as a keystroke, so a macro does exactly what typing
would: `/rfc~A1.A5~` formats a range.

## Running macros
- **Alt-letter** runs the range named `\` plus that letter (a macro named `\A`
  is run with Alt-A).  Name it with `/Range Name Create`; macro names are a
  backslash and one letter or digit.
- **Alt-F3** lists the range names; pick one to run it.
- **`\0`** runs automatically when a file is retrieved or given on the command
  line.
- **Ctrl-Break** stops a macro.  `CMD` shows at the bottom while one is running
  or paused.

## Keystrokes
`~` is Enter.  `{UP}` `{DOWN}` `{LEFT}` `{RIGHT}` `{HOME}` `{END}` `{PGUP}`
`{PGDN}` `{BIGLEFT}` `{BIGRIGHT}` `{DEL}` `{BS}` `{ESC}` `{EDIT}` `{NAME}`
`{ABS}` `{GOTO}` `{WINDOW}` `{QUERY}` `{TABLE}` `{CALC}` `{GRAPH}` `{HELP}`,
with an optional count (`{DOWN 5}`).  `{{}` and `{}}` type braces, `{~}` a
tilde.  `{?}` pauses until the user presses Enter.

## Commands
| Command | Meaning |
|---|---|
| `{BRANCH loc}` | continue at loc |
| `{IF expr}` | rest of the cell runs only if expr is true; otherwise go to the next cell |
| `{QUIT}` `{RETURN}` `{RESTART}` | end the macro / end a routine / forget the call stack |
| `{name arg,arg}` | call the routine at range name `name`; `{DEFINE loc:string,loc}` receives the arguments |
| `{FOR counter,start,stop,step,loc}` `{FORBREAK}` | repeat the routine at loc |
| `{MENUBRANCH loc}` `{MENUCALL loc}` | a menu: items in the row at loc, descriptions below, macros below that |
| `{LET loc,expr}` | store a number, text or formula result (`:string` / `:value` force the type) |
| `{PUT range,col,row,expr}` `{BLANK range}` `{CONTENTS dest,source}` | write, erase, copy displayed text |
| `{GETLABEL prompt,loc}` `{GETNUMBER prompt,loc}` | ask the user |
| `{GET loc}` `{LOOK loc}` | wait for one key / peek (always empty) |
| `{RECALC}` `{RECALCCOL}` | recalculate |
| `{INDICATE text}` | replace the mode indicator |
| `{BEEP}` `{WAIT}` `{PANELOFF}` `{PANELON}` `{WINDOWSOFF}` `{WINDOWSON}` `{BREAKOFF}` `{BREAKON}` `{ONERROR}` | accepted, no effect |

Not implemented: the file commands (`{OPEN}`, `{READ}`, `{WRITE}` ...),
`{SYSTEM}`, `{DISPATCH}`, `{GETPOS}`/`{SETPOS}`, `{FILESIZE}`, macro recording
and STEP mode.  An unknown command ends the macro with a message.
A macro that branches in a loop without typing anything is stopped.
