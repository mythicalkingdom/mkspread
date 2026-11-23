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
tilde.  `{?}` pauses until the user presses Enter; that Enter only resumes the macro (it is not typed), so text typed meanwhile continues with the macro's next keys.

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

## Recording (LEARN) and STEP
- **`/Worksheet Learn Range`** sets the range where keystrokes are recorded;
  `Cancel` forgets it, `Erase` empties it.
- **Alt-F5** turns recording on and off (`LEARN` at the bottom).  Every key you
  type is written into the learn range as macro text (`~` for Enter, `{DOWN}`,
  `{{}` for a brace ...), starting at the first empty cell, down the column and
  then across; a line is cut at 100 characters.  Name the first cell `\A` and
  the recording is a macro.
- **Alt-F2** turns STEP mode on and off (`STEP` at the bottom).  While it is on a
  macro waits before every key and command and shows its current line with `>`
  at the position; any key steps (the key itself is not typed).  Alt-F2 during a
  step switches STEP off and the macro runs on.

Not implemented: the file commands (`{OPEN}`, `{READ}`, `{WRITE}` ...),
`{SYSTEM}`, `{DISPATCH}`, `{GETPOS}`/`{SETPOS}`, `{FILESIZE}`.  An unknown command ends the macro with a message.
A macro that branches in a loop without typing anything is stopped.
