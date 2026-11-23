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
