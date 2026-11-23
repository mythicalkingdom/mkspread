#!/usr/bin/env python3
"""End-to-end screen tests: run the real binary in a pty and inspect the screen."""
import os, sys, time
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


def run(args=(), rows=25, cols=80, cwd=None):
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
    8: "4    Materials                  $3.26         Plant Operation",
    12: "8    Freight                    $0.32         Research & Development",
    13: "9                           ---------",
    14: "10   Total                     $10.99",
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
check(s.line(3) == 'Global, Insert, Delete, Column, Erase, Titles, Window, Status, Page', 'submenu list', s.line(3))
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
s.send('\x1bOS')     # F4 (xterm)
check('F4' in s.line(25), 'F4 recognised', s.line(25))
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
check(s.line(6).rstrip().endswith('42') and len(s.line(6).rstrip()) == 4 + 9, 'number right aligned in cell', repr(s.line(6)))
s.send('/qy', 0.4)
s.close()


# ---- phase 3: formats, EDIT, POINT, widths, undo ----
s = run()
s.send('1234.5\r')
s.send('/rfc', 0.4)
check(s.line(1).endswith('EDIT') and 'Enter number of decimal places (0..15): 2' in s.line(2), 'decimal places prompt', s.line(2))
s.send('\r')
check(s.line(1).endswith('POINT') and s.line(2).startswith('Enter range to format: A1'), 'range prompt', s.line(2))
s.send('.\x1b[B')
check(s.line(2).startswith('Enter range to format: A1..A2'), 'range grows with arrows', s.line(2))
check(s.screen.cyan(4)[4:13] == '#########' and s.screen.cyan(5)[4:13] == '#########', 'range highlighted')
s.send('\r')
check(s.line(5).rstrip().endswith('$1,234.50'), 'currency applied', s.line(5))
check(s.line(1).startswith('A1: (C2) 1234.5'), 'status line shows format tag', s.line(1))
check('UNDO' in s.line(25), 'UNDO indicator', s.line(25))
s.send('\x15')
check(s.line(5).rstrip().endswith('1234.5') and '$' not in s.line(5), 'Ctrl-U undoes the format', s.line(5))
# EDIT mode
s.send('\x1bOQ')   # F2
check(s.line(1).endswith('EDIT') and s.line(2).startswith('1234.5'), 'F2 edit mode', s.line(2))
s.send('\x1b[D\x1b[D9')
check(s.line(2).startswith('12349.5'), 'edit inserts at cursor', s.line(2))
s.send('\r')
check(s.line(5).rstrip().endswith('12349.5'), 'edit committed', s.line(5))
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
s.send('/qy', 0.4)
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
s.send('/qy', 0.4)
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
s.send('/qy', 0.4)
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
s.send('/qy', 0.4)
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
    s.send('/qy', 0.4)
    s.close()

    s = run(['sheet.WK1'], cwd=d)
    check(s.line(5).rstrip().endswith('7'), 'file given on the command line is opened', s.line(5))
    check(s.line(6).rstrip().endswith('42'), 'its formula is calculated', s.line(6))
    check(s.line(1).startswith('A3:'), 'pointer where it was saved', s.line(1))
    s.send('/fr')
    check('Enter name of file to retrieve:' in s.line(2), 'retrieve prompt', s.line(2))
    s.send('\x1bOR')
    check(s.line(1).endswith('NAMES') and s.line(2).startswith('sheet.WK1'), 'F3 lists the files', s.line(1) + s.line(2))
    s.send('\r')
    s.send('\r')
    check(s.line(5).rstrip().endswith('7'), 'retrieve from the list', s.line(5))
    s.send('/fr')
    s.send('nothing\r')
    check('File not found: nothing' in s.line(25), 'missing file', s.line(25))
    s.send('/qy', 0.4)
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
check(s.line(7).rstrip().endswith('there') or 'there' in s.line(8), 'macro continued after the user pressed Enter', s.line(7) + s.line(8))
check('CMD' not in s.line(25), 'CMD indicator gone when the macro ends', s.line(25))
s.send('/qy', 0.4)
s.close()

# ---- screen size handling ----
s = run(rows=20, cols=70)
check('too small' in s.line(1), 'small terminal message', s.line(1))
s.send('/qy', 0.3)
s.close()
s = run(['--expand'], rows=30, cols=100)
check(s.line(4).split()[-1] == 'L' or len(s.line(4).split()) >= 10, 'expand shows more columns', s.line(4))
check(s.line(30)[:3].strip() != '' , 'expand uses bottom of tall terminal', s.line(30))
check(s.line(29).startswith('25'), 'expand shows 25 rows', s.line(29))
s.send('/qy', 0.3)
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
