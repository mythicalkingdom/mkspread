#!/usr/bin/env python3
"""Compare the .PRN files made by the original program with mkspread's.

usage: cmp_print.py <mkspread dir> <original-program dir> [-v]
Line ends (CRLF), a final Ctrl-Z and trailing blanks are ignored; everything else
must match.  Prints the first differences of every file that differs."""
import sys, os, difflib


def load(path):
    data = open(path, 'rb').read()
    data = data.replace(b'\r\n', b'\n').rstrip(b'\x1a')
    lines = data.decode('cp437', 'replace').split('\n')
    return [l.rstrip(' ') for l in lines]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    mine, theirs = sys.argv[1], sys.argv[2]
    names = sorted(f for f in os.listdir(mine) if f.upper().endswith('.PRN'))
    bad = 0
    for n in names:
        other = None
        for f in os.listdir(theirs):
            if f.upper() == n.upper():
                other = os.path.join(theirs, f)
        if other is None:
            print(n, ': missing in', theirs)
            bad += 1
            continue
        a, b = load(os.path.join(mine, n)), load(other)
        # trailing empty lines carry no information
        while a and a[-1] == '': a.pop()
        while b and b[-1] == '': b.pop()
        if a == b:
            print(n, ': same')
            continue
        bad += 1
        print(n, ': DIFFERENT (mkspread %d lines, original %d lines)' % (len(a), len(b)))
        shown = 0
        for l in difflib.unified_diff(a, b, 'mkspread', 'original', lineterm='', n=1):
            print('   ', repr(l)[1:-1] if l[:1] in '+-' else l)
            shown += 1
            if shown > 24 and '-v' not in sys.argv:
                print('    ...')
                break
    print('%d of %d files differ' % (bad, len(names)))
    return 1 if bad else 0


sys.exit(main())
