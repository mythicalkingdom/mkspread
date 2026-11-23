#!/usr/bin/env python3
"""End-to-end screen tests: run the real binary in a pty and inspect the screen."""
import os, sys, time, tempfile, shutil
sys.path.insert(0, os.path.dirname(__file__))
from term import Session

BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'mkspread')
fails = total = 0


def check(cond, what, detail=''):
    global fails, total
    total += 1
    if not cond:
        fails += 1
        print('FAIL:', what, detail)


STATE = tempfile.mkdtemp(prefix='mkspread_state_')
os.environ['XDG_STATE_HOME'] = STATE          # recovery files of the test runs go here
os.environ['XDG_CONFIG_HOME'] = os.path.join(STATE, 'config')


def clean_state():
    shutil.rmtree(os.path.join(STATE, 'mkspread'), ignore_errors=True)


def quit(s):
    """/Quit Yes, and Yes again when there are unsaved changes."""
    s.send('/qy', 0.4)
    if s.alive and s.line(2).startswith('No  Yes'):
        s.send('y', 0.4)


def run(args=(), rows=25, cols=80, cwd=None):
    clean_state()
    return Session([BIN] + list(args), rows, cols, cwd=cwd)


# ---- empty start-up screen ----
s = run()
check(s.line(1).startswith('A1:'), 'status line shows A1', s.line(1))
check(s.line(1).endswith('READY'), 'READY indicator', s.line(1))
check(s.screen.cyan(0)[-5:] == '#####', 'READY is highlighted')
check(s.screen.cyan(3) == '#' * 80, 'column header row is cyan')
check(s.line(4).split() == list('ABCDEFGH'), 'default columns A-H', s.line(4))
check(s.line(5).startswith('1'), 'row 1 on line 5')
check(s.line(24).startswith('20'), 'row 20 on line 24', s.line(24))
check(s.line(25)[:3].strip() != '' and '-' in s.line(25)[:10], 'clock on bottom line', s.line(25))
s.send('/qy', 0.5)
check(not s.alive, '/QY exits the program')
s.close()

# ---- demo sheet reproduces the reference screenshot ----
s = run(['--demo'])
expect = {
    1: "K4: [W23] 'Materials",
    4: "    J           K               L        M               N                O",
    5: "1         Variable Costs/Unit                           Fixed Costs",
    6: "2    Description            Cost/Unit         Description",
    7: "3    ================================         ========================",
    8: "4    Materials                 $3.26          Plant Operation",
    12: "8    Freight                   $0.32          Research & Development",
    13: "9                           ---------",
    14: "10   Total                    $10.99",
}
for n, text in expect.items():
    got = s.line(n)
    check(got.startswith(text), 'demo line %d' % n, '\n   got  %r\n   want %r' % (got, text))
# cursor highlight covers K4 (23 columns starting at screen column 6)
check(s.screen.cyan(7)[5:28] == '#' * 23 and s.screen.cyan(7)[28] == '.', 'cell cursor highlight', s.screen.cyan(7))

# ---- menus ----
s.send('/')
check(s.line(1).endswith('MENU'), 'MENU indicator', s.line(1))
check(s.line(2).startswith('Worksheet  Range  Copy  Move  File  Print  Graph  Data  System  Quit'), 'menu bar', s.line(2))
check(s.line(3) == 'Global, Insert, Delete, Column, Erase, Titles, Window, Status, Page, Learn', 'submenu list', s.line(3))
check(s.screen.cyan(1)[:9] == '#########' and s.screen.cyan(1)[9] == '.', 'first item highlighted')
s.send('\x1b[C')  # right arrow
check(s.line(3).startswith('Format, Label, Erase, Name'), 'right arrow moves to Range', s.line(3))
s.send('\r')
s.send('f')       # Format
check(s.line(2).startswith('Fixed  Sci  Currency'), 'Range Format menu', s.line(2))
s.send('\x1b')    # lone Esc backs up one level (must not be taken for Alt-key)
time.sleep(0.2)
s.send('')
check(s.line(2).startswith('Format  Label  Erase'), 'Esc goes back one level', s.line(2))
s.send('\x1b'); s.send('')
s.send('\x1b'); s.send('')
check(s.line(1).endswith('READY'), 'Esc leaves menu', s.line(1))
s.send('/wgpe', 0.4)
check('[stub] /Worksheet Global Protection Enable' in s.line(25), 'stub message', s.line(25))
check(s.line(1).endswith('READY'), 'back in READY after command')
s.send('x')
check('[stub]' not in s.line(25), 'message clears on next key')
s.send('\x1b')
s.send('/qn')
check(s.alive and s.line(1).endswith('READY'), '/QN stays')

# ---- key mapping ----
s.send('\x1b[1;5C')  # Ctrl-Right (xterm)
check(s.line(1).startswith('S4:') or s.line(1).startswith('T4:') or s.line(1)[0] in 'MNOPQRSTU',
      'Ctrl-Right moves a screen right', s.line(1))
s.send('\x1bx')      # Alt-X
check('No macro \\X is defined' in s.line(25), 'Alt-letter recognised', s.line(25))
s.send('\x1bOS')     # F4 (xterm) does nothing in READY
check(s.line(1).endswith('READY'), 'F4 in READY is harmless', s.line(1))
s.send('\x1b[1;3S')  # Alt-F4
check('Nothing to undo' in s.line(25), 'Alt-F4 recognised as Undo', s.line(25))
s.send('\x15')       # Ctrl-U equivalent
check('Nothing to undo' in s.line(25), 'Ctrl-U is the Alt-F4 alternative', s.line(25))
s.send('\x1b[15~')   # F5 = goto
check('Enter address to go to' in s.line(2), 'F5 goto prompt', s.line(2))
s.send('b3\r')
check(s.line(1).startswith('B3:'), 'goto B3', s.line(1))
s.close()

# ---- entry, including UTF-8 ----
s = run()
s.send('café')
check(s.line(1).endswith('LABEL') and s.line(2).startswith("'café"), 'label entry shows text', s.line(2))
s.send('\r')
check(s.line(5).startswith('1   café'), 'UTF-8 label displayed', s.line(5))
check(s.line(1).startswith("A1: 'café"), 'status shows raw contents', s.line(1))
s.send('\x1b[B')
s.send('42\r')
check(s.line(6).rstrip().endswith('42') and len(s.line(6).rstrip()) == 4 + 8, 'number right aligned in cell', repr(s.line(6)))
quit(s)
s.close()


# ---- phase 3: formats, EDIT, POINT, widths, undo ----
s = run()
s.send('123.5\r')
s.send('/rfc', 0.4)
check(s.line(1).endswith('EDIT') and 'Enter number of decimal places (0..15): 2' in s.line(2), 'decimal places prompt', s.line(2))
s.send('\r')
check(s.line(1).endswith('POINT') and s.line(2).startswith('Enter range to format: A1'), 'range prompt', s.line(2))
s.send('.\x1b[B')
check(s.line(2).startswith('Enter range to format: A1..A2'), 'range grows with arrows', s.line(2))
check(s.screen.cyan(4)[4:13] == '#########' and s.screen.cyan(5)[4:13] == '#########', 'range highlighted')
s.send('\r')
check(s.line(5).rstrip().endswith('$123.50'), 'currency applied', s.line(5))
check(s.line(1).startswith('A1: (C2) 123.5'), 'status line shows format tag', s.line(1))
check('UNDO' in s.line(25), 'UNDO indicator', s.line(25))
s.send('\x15')
check(s.line(5).rstrip().endswith('123.5') and '$' not in s.line(5), 'Ctrl-U undoes the format', s.line(5))
# EDIT mode
s.send('\x1bOQ')   # F2
check(s.line(1).endswith('EDIT') and s.line(2).startswith('123.5'), 'F2 edit mode', s.line(2))
s.send('\x1b[D\x1b[D9')
check(s.line(2).startswith('1239.5'), 'edit inserts at cursor', s.line(2))
s.send('\r')
check(s.line(5).rstrip().endswith('1239.5'), 'edit committed', s.line(5))
# column width with live preview
s.send('/wcs')
s.send('\x1b[C\x1b[C\x1b[C')
check('Enter column width (1..240): 12' in s.line(2), 'width prompt', s.line(2))
check(s.line(4).split()[:3] == ['A', 'B', 'C'] and s.line(4).index('B') - s.line(4).index('A') == 11, 'width previewed live', s.line(4))
s.send('\r')
check(s.line(4).index('B') - s.line(4).index('A') == 11, 'width kept')
check(s.line(1).startswith('A1: [W12]'), 'status shows [W12]', s.line(1))
# date format
s.send('/rfd1\r')
check(s.line(5).rstrip().endswith('23-Sep-33') or '-' in s.line(5), 'date format applied', s.line(5))
quit(s)
s.close()

# ---- phase 4: formulas on screen ----
s = run()
s.send('5\r')
s.send('\x1b[B')
s.send('+a1*2\r')
check(s.line(6).rstrip().endswith('10'), 'formula result displayed', s.line(6))
check(s.line(1).startswith('A2: +A1*2'), 'status line shows the formula', s.line(1))
s.send('1+\r')
check(s.line(1).endswith('EDIT') and 'Invalid formula' in s.line(25), 'bad formula goes to EDIT', s.line(1) + s.line(25))
s.send('\x1b')
s.send('/wgrm')
s.send('\x1b[A9\r')
check('CALC' in s.line(25), 'CALC indicator in manual mode', s.line(25))
check(s.line(6).rstrip().endswith('10'), 'not recalculated yet', s.line(6))
s.send('\x1b[20~')   # F9
check('CALC' not in s.line(25) and s.line(6).rstrip().endswith('18'), 'F9 recalculates', s.line(6) + s.line(25))
s.send('\x1b[B\x1b[B+b3\r\x1b[C+a3\r')
s.send('\x1b[20~')   # manual mode: F9 to find the cycle
check('CIRC' in s.line(25), 'CIRC indicator', s.line(25))
quit(s)
s.close()

# ---- phase 5: copy, titles, names on screen ----
s = run()
s.send('5\r')
s.send('\x1b[C+a1*2\r')
s.send('/c')
check(s.line(1).endswith('POINT') and s.line(2).startswith('Enter range to copy FROM:'), 'copy FROM prompt', s.line(2))
s.send('\r')
check(s.line(2).startswith('Enter range to copy TO:'), 'copy TO prompt', s.line(2))
s.send('\x1b[B.\x1b[B\x1b[B')
check(s.line(2).startswith('Enter range to copy TO: B2..B4') or s.line(2).startswith('Enter range to copy TO: A3..B4') or '..' in s.line(2), 'range grows', s.line(2))
s.send('\r')
s.close()

s = run()
s.send('H\r')
s.send('\x1b[B/wth')       # freeze row 1
s.send('\x1b[6~')            # PgDn
check(s.line(5).startswith('1   H') or s.line(5).startswith("1   H"), 'title row stays on top', s.line(5))
check(s.line(6).startswith('21'), 'scrolling rows start below the titles', s.line(6))
check(s.line(1).startswith('A21:'), 'pointer moved a screen', s.line(1))
quit(s)
s.close()

s = run()
s.send('5\r')
s.send('/rnc')
check('Enter name:' in s.line(2), 'name prompt', s.line(2))
s.send('tax\r')
check(s.line(2).startswith('Enter range:'), 'range prompt', s.line(2))
s.send('\r')
s.send('\x1b[B+tax*2\r')
check(s.line(6).rstrip().endswith('10'), 'formula using a range name', s.line(6))
check(s.line(1).startswith('A2: +TAX*2'), 'name shown upper case in the status line', s.line(1))
s.send('/c\x1bOR')          # F3 inside a range prompt
check(s.line(1).endswith('NAMES') and s.line(2).startswith('TAX'), 'F3 lists names', s.line(1) + s.line(2))
s.send('\x1b')
s.send('\x1b')
quit(s)
s.close()

# ---- phase 6: files ----
import tempfile, shutil
d = tempfile.mkdtemp(prefix='mkspread_ui_')
try:
    s = run(cwd=d)
    s.send('7\r')
    s.send('\x1b[B+a1*6\r')
    s.send('\x1b[B/rfc\r')
    s.send('\r')
    s.send('\r')
    s.send('/fs')
    check('Enter name of file to save:' in s.line(2), 'save prompt', s.line(2))
    s.send('sheet\r')
    check('Saved sheet.WK1' in s.line(25), 'saved message', s.line(25))
    check(os.path.exists(os.path.join(d, 'sheet.WK1')), 'file written')
    s.send('/fs\r')
    check(s.line(1).endswith('NAMES') and s.line(2).startswith('Cancel  Replace'), 'asks before replacing', s.line(1) + s.line(2))
    s.send('\x1b')
    quit(s)
    s.close()

    s = run(['sheet.WK1'], cwd=d)
    check(s.line(5).rstrip().endswith('7'), 'file given on the command line is opened', s.line(5))
    check(s.line(6).rstrip().endswith('42'), 'its formula is calculated', s.line(6))
    check(s.line(1).startswith('A3:'), 'pointer where it was saved', s.line(1))
    s.send('/fr')
    check('Enter name of file to retrieve:' in s.line(2), 'retrieve prompt', s.line(2))
    check(s.line(1).endswith('NAMES') and s.line(3).startswith('sheet.WK1'), 'the files are listed at once', s.line(1) + s.line(3))
    s.send('\x1b')
    check(s.line(1).endswith('EDIT') or s.line(1).endswith('POINT') or 'retrieve' in s.line(2), 'Esc goes to typing a name', s.line(1) + s.line(2))
    s.send('\x1bOR')
    check(s.line(1).endswith('NAMES') and s.line(3).startswith('sheet.WK1'), 'F3 lists the files again', s.line(1) + s.line(3))
    s.send('\r')
    s.send('\r')
    check(s.line(5).rstrip().endswith('7'), 'retrieve from the list', s.line(5))
    s.send('/fr')
    s.send('nothing\r')
    check('File not found: nothing' in s.line(25), 'missing file', s.line(25))
    quit(s)
    s.close()

    with open(os.path.join(d, 'bad.wk1'), 'w') as fh:
        fh.write('not a worksheet')
    p = os.popen('cd %s && %s bad.wk1 2>&1' % (d, BIN))
    out = p.read()
    p.close()
    check('Not a worksheet file' in out, 'a bad file on the command line is reported', out)
finally:
    shutil.rmtree(d, ignore_errors=True)

# ---- phase 8: macros on screen ----
s = run()
s.send('\x1b[15~k1\r')                         # F5 K1
s.send("'{DOWN}hi~{DOWN}{?}there~\r")           # macro text: types hi, pauses for the user, then 'there'
s.send('/rnc\\a\r\r')                          # /Range Name Create \a, range = K1
s.send('\x1b[15~a1\r')
s.send('\x1ba')                                  # Alt-A runs \A
check(s.line(6).startswith('2   hi'), 'macro typed into the worksheet', s.line(6))
check('CMD' in s.line(25), 'CMD indicator while a macro waits', s.line(25))
s.send('ab\r')
check('abthere' in s.line(7) + s.line(8), 'macro continued after the user pressed Enter (Enter not stored)', s.line(7) + s.line(8))
check('CMD' not in s.line(25), 'CMD indicator gone when the macro ends', s.line(25))
quit(s)
s.close()

# ---- learn and step indicators ----
s = run()
s.send('/wlr')
s.send('k1.k5\r')
s.send('\x1b[15;3~')              # Alt-F5
check('LEARN' in s.line(25), 'LEARN indicator while recording', s.line(25))
s.send('hi\r')
s.send('\x1b[15;3~')
check('LEARN' not in s.line(25), 'LEARN indicator off', s.line(25))
s.send('\x1b[1;3Q')               # Alt-F2
check('STEP' in s.line(25), 'STEP indicator', s.line(25))
s.send('\x1b[1;3Q')
check('STEP' not in s.line(25), 'STEP indicator off', s.line(25))
quit(s)
s.close()

# ---- phase 9: /Data commands on screen ----
s = run()
s.send('/df')
check(s.line(2).startswith('Enter fill range:'), 'fill range prompt', s.line(2))
s.send('a1.a5\r')
check(s.line(2).startswith('Start: 0'), 'start prompt with its default', s.line(2))
s.send('\x7f1\r')       # backspace, 1
s.send('\x7f2\r')
s.send('\r')
check(s.line(5).rstrip().endswith('1') and s.line(6).rstrip().endswith('3') and s.line(9).rstrip().endswith('9'),
      'a column filled 1, 3, 5, 7, 9', s.line(5) + s.line(6) + s.line(9))
# find mode on a small database
s.send('\x1b[15~c1\r')
s.send("Name\r\x1b[B")
s.send("Ann\r\x1b[B")
s.send("Bob\r")
s.send('\x1b[15~e1\r')
s.send("Name\r\x1b[B")
s.send("Bob\r")
s.send('/dqi')
s.send('c1.c3\r')
s.send('c')
s.send('e1.e2\r')
s.send('f')
check(s.line(1).endswith('FIND'), 'FIND indicator', s.line(1))
check(s.line(1).startswith('C3:'), 'the pointer is on the matching record', s.line(1))
s.send('\x1b')
check(s.line(1).endswith('MENU'), 'Esc in FIND returns to the Query menu', s.line(1))
s.send('\x1b\x1b\x1b')
check(s.line(1).endswith('READY'), 'Esc leaves the menu', s.line(1))
quit(s)
s.close()

# ---- the Sort menu comes back after each setting; Go ends it ----
s = run()
s.send('/ds')
s.send('d')
s.send('a1.a3\r')
check(s.line(1).endswith('MENU'), 'the Sort menu returns after Data-Range', s.line(1))
s.send('q')
check(s.line(1).endswith('READY'), 'Quit leaves the Sort menu', s.line(1))
s.send('/ds')
s.send('p')
s.send('a1\r')
s.send('d')                      # replaces the default A
s.send('\r')
check(s.line(1).endswith('MENU'), 'the Sort menu returns after a key', s.line(1))
s.send('\x1b\x1b')
quit(s)
s.close()

# ---- F4 and pointing in formulas ----
s = run()
s.send('5\r')                       # A1 = 5
s.send('\x1b[B')                    # A2
s.send('+a1')
s.send('\x1bOS')                    # F4: $A$1
check(s.line(2).startswith('+$A$1'), 'F4 makes the reference absolute', s.line(2))
s.send('\x1bOS')
check(s.line(2).startswith('+A$1'), 'F4 again: row absolute', s.line(2))
s.send('\x1bOS'); s.send('\x1bOS')
check(s.line(2).startswith('+A1'), 'and back to relative', s.line(2))
s.send('\x1b')
s.send('+')
s.send('\x1b[A')                    # point at A1 with the arrow
check(s.line(1).endswith('POINT') and s.line(2).startswith('+A1'), 'an arrow after + points at a cell', s.line(1) + s.line(2))
s.send('\x1bOS')
check(s.line(2).startswith('+$A$1'), 'F4 while pointing', s.line(2))
s.send('*2\r')
check(s.line(1).startswith('A2:') and s.line(1).endswith('READY'), 'the pointer is back after the entry', s.line(1))
check(s.line(6).rstrip().endswith('10'), 'the formula was entered (+$A$1*2 = 10)', s.line(6))
quit(s)
s.close()

# ---- defaults and the quit confirmation ----
s = run()
s.send('/wgds', 0.5)
check(s.line(1).endswith('HELP') and 'Printer' in s.line(3) and 'Page length 66' in s.line(6), 'Default Status shows the settings', s.line(3) + s.line(6))
s.send('\x1b', 0.3)
check(s.line(1).endswith('MENU'), 'Esc returns to the Default menu', s.line(1))
s.send('\x1b\x1b\x1b\x1b', 0.3)
s.send('5\r/qy', 0.5)
check(s.line(2).startswith('No  Yes') and 'unsaved changes' in s.line(25), 'Quit asks again when the worksheet changed', s.line(2) + s.line(25))
s.send('n', 0.3)
check(s.alive and s.line(1).endswith('READY'), 'No stays', s.line(1))
quit(s)
check(not s.alive, 'Yes quits')
s.close()

# ---- recovery ----
import signal, glob
rec = os.path.join(STATE, 'mkspread', 'recover')
s = run()
s.send('5\r')
s.send('\x1b[B')
s.send('abc\r')
os.kill(s.pid, signal.SIGHUP)          # the terminal goes away
s.close()
check(len(glob.glob(rec + '/*.wk1')) == 1, 'a hangup leaves a recovery file', str(glob.glob(rec + '/*')))
s = Session([BIN], 25, 80)               # not run(): that would clean the state folder
check(s.line(2).startswith('Recover'), 'the next start offers the recovery', s.line(2))
check('Load the unsaved worksheet' in s.line(3), 'with an explanation', s.line(3))
s.send('\r')
check(s.line(5).rstrip().endswith('5') and 'abc' in s.line(6), 'the worksheet is recovered', s.line(5) + s.line(6))
check(not glob.glob(rec + '/*.wk1'), 'the recovery file is gone', str(glob.glob(rec + '/*')))
quit(s)
s.close()
check(not glob.glob(rec + '/*'), 'a clean exit leaves nothing', str(glob.glob(rec + '/*')))
# discard, and the periodic write
os.makedirs(os.path.join(STATE, 'config', 'mkspread'), exist_ok=True)
open(os.path.join(STATE, 'config', 'mkspread', 'mkspread.conf'), 'w').write('recovery = 1\n')
s = run()
s.send('7\r', 2.5)
check(len(glob.glob(rec + '/*.wk1')) == 1, 'the recovery file is written while working', str(glob.glob(rec + '/*')))
os.kill(s.pid, signal.SIGKILL)         # no chance to clean up
s.close()
s = Session([BIN], 25, 80)
check(s.line(2).startswith('Recover'), 'offered after a crash', s.line(2))
s.send('d')
check(s.line(5).strip() == '1' and not glob.glob(rec + '/*.wk1'), 'Discard deletes it', s.line(5))
quit(s)
s.close()
os.remove(os.path.join(STATE, 'config', 'mkspread', 'mkspread.conf'))

# ---- windows ----
s = run()
s.send('\x1b[B' * 9, 0.2)
s.send('/wwh', 0.4)
check(s.line(1).startswith('A10:'), 'the pointer stays on its cell after a split', s.line(1))
s.send('\x1b[17~', 0.3)
check(s.line(1).startswith('A9:'), 'F6 moves to the upper window', s.line(1))
s.send('/wwc', 0.3)
check(s.line(1).startswith('A9:'), 'Clear keeps the pointer', s.line(1))
quit(s)
s.close()

# ---- print menu ----
s = run()
s.send('/pp', 0.3)
check(s.line(2).startswith('Range  Line  Page  Options  Clear  Align  Go  Quit'), 'the print menu opens after Printer', s.line(2))
s.send('g', 0.3)
check('Specify a print range first' in s.line(25) and s.line(1).endswith('MENU'), 'Go without a range says so and the menu stays', s.line(25) + s.line(1))
s.send('q', 0.3)
check(s.line(1).endswith('READY'), 'Quit leaves the menu', s.line(1))
quit(s)
s.close()

# ---- help screens ----
s = run()
s.send('\x1bOP', 0.3)
check(s.line(1).startswith(' Getting started') and s.line(1).endswith('HELP'), 'F1 shows a help screen', s.line(1))
check('See also:' in s.line(23), 'related topics are listed', s.line(23))
s.send('\x1bOP', 0.3)
check(s.line(1).startswith(' Help Index'), 'F1 again shows the index', s.line(1))
check(s.line(6).strip().startswith('Getting started') and any('Macros' in s.line(n) for n in range(6, 23)), 'the index lists topics in two columns', s.line(6))
s.send('\x1b', 0.3)
check(s.line(1).endswith('READY'), 'Esc leaves help', s.line(1))
s.send('/', 0.3)
s.send('\x1b[C', 0.3)
s.send('\x1bOP', 0.3)
check(s.line(1).startswith(' Range commands'), 'F1 in the menu explains the choice', s.line(1))
s.send('\x1b', 0.3)
check(s.line(1).endswith('MENU'), 'back in the menu', s.line(1))
s.send('\x1b/qy', 0.4)
s.close()

# ---- STEP shows the macro line ----
s = run()
s.send('\x1b[15~k1\r')
s.send("'{DOWN}hi~\r")
s.send('/rnc\\a\r\r')
s.send('\x1b[15~a1\r')
s.send('\x1b[1;3Q')                      # Alt-F2: STEP on
s.send('\x1ba')                           # run \A
check(s.line(3).startswith('K1: >{DOWN}hi~'), 'STEP shows the macro line with the position', s.line(3))
check('STEP' in s.line(25) and 'CMD' in s.line(25), 'STEP and CMD indicators', s.line(25))
s.send('x')
check(s.line(3).startswith('K1: {DOWN}>hi~'), 'the marker moves one key per step', s.line(3))
s.send('\x1b[1;3Q')                      # Alt-F2: run on
check('STEP' not in s.line(25), 'STEP off', s.line(25))
quit(s)
s.close()

# ---- screen size handling ----
s = run(rows=20, cols=70)
check('too small' in s.line(1), 'small terminal message', s.line(1))
quit(s)
s.close()
s = run(['--expand'], rows=30, cols=100)
check(s.line(4).split()[-1] == 'L' or len(s.line(4).split()) >= 10, 'expand shows more columns', s.line(4))
check(s.line(30)[:3].strip() != '' , 'expand uses bottom of tall terminal', s.line(30))
check(s.line(29).startswith('25'), 'expand shows 25 rows', s.line(29))
quit(s)
s.close()

# ---- key test mode ----
s = run(['--keytest'])
s.send('\x1b[1;5C')
s.send('\x1b[1;3P')
s.send('\x1bz')
text = '\n'.join(s.screen.lines())
check('Ctrl-Right' in text and 'Alt-F1' in text and 'Alt-Z' in text, 'keytest names keys', text)
s.send('\x11', 0.4)
check(not s.alive, 'Ctrl-Q leaves keytest')
s.close()

print('%d/%d UI checks passed' % (total - fails, total))
sys.exit(1 if fails else 0)
