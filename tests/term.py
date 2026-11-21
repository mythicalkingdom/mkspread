"""Tiny pty-based terminal driver + screen renderer used by the UI tests.

Runs a program in a pseudo-terminal of a given size, sends keystrokes, and
renders the output through a minimal xterm-style screen model so tests can
compare what the user would see.  No third-party modules needed.
"""
import fcntl, os, pty, re, select, struct, termios, time

CSI = re.compile(r'\x1b\[([0-9;?]*)([@-~])')


class Screen:
    def __init__(self, rows=25, cols=80):
        self.rows, self.cols = rows, cols
        self.reset()

    def reset(self):
        self.ch = [[' '] * self.cols for _ in range(self.rows)]
        self.at = [[0] * self.cols for _ in range(self.rows)]   # 0 normal, 1 cyan background
        self.x = self.y = 0
        self.cur = 0
        self.last = ' '

    def put(self, c):
        if self.x >= self.cols:
            self.x = 0
            self.y += 1
        if 0 <= self.y < self.rows:
            self.ch[self.y][self.x] = c
            self.at[self.y][self.x] = self.cur
        self.last = c
        self.x += 1

    def feed(self, data):
        s = data.decode('utf-8', 'replace')
        i = 0
        while i < len(s):
            c = s[i]
            if c == '\x1b':
                m = CSI.match(s, i)
                if m:
                    self.csi(m.group(1), m.group(2))
                    i = m.end()
                    continue
                # ESC ( B, ESC =, ESC > and similar: skip 2 (or 3) chars
                if i + 1 < len(s) and s[i + 1] in '()':
                    i += 3
                else:
                    i += 2
                continue
            if c == '\r':
                self.x = 0
            elif c == '\n':
                self.y = min(self.y + 1, self.rows - 1)
            elif c == '\b':
                self.x = max(0, self.x - 1)
            elif c == '\x0f' or c == '\x0e' or c == '\x07':
                pass
            elif c >= ' ':
                self.put(c)
            i += 1

    def csi(self, p, f):
        a = [int(v) if v.isdigit() else 0 for v in p.replace('?', '').split(';')] if p else []
        n = a[0] if a and a[0] else 1
        if p.startswith('?'):
            return
        if f in 'Hf':
            self.y = (a[0] - 1) if a and a[0] else 0
            self.x = (a[1] - 1) if len(a) > 1 and a[1] else 0
        elif f == 'A': self.y = max(0, self.y - n)
        elif f == 'B': self.y = min(self.rows - 1, self.y + n)
        elif f == 'C': self.x = min(self.cols - 1, self.x + n)
        elif f == 'D': self.x = max(0, self.x - n)
        elif f == 'G': self.x = n - 1
        elif f == 'd': self.y = n - 1
        elif f == 'J':
            mode = a[0] if a else 0
            if mode == 2 or mode == 3:
                self.ch = [[' '] * self.cols for _ in range(self.rows)]
                self.at = [[0] * self.cols for _ in range(self.rows)]
            elif mode == 0:
                for x in range(self.x, self.cols): self.ch[self.y][x] = ' '; self.at[self.y][x] = self.cur
                for y in range(self.y + 1, self.rows):
                    self.ch[y] = [' '] * self.cols; self.at[y] = [self.cur] * self.cols
        elif f == 'K':
            mode = a[0] if a else 0
            rng = range(self.x, self.cols) if mode == 0 else range(0, self.x + 1) if mode == 1 else range(self.cols)
            for x in rng: self.ch[self.y][x] = ' '; self.at[self.y][x] = self.cur
        elif f == 'X':
            for x in range(self.x, min(self.cols, self.x + n)): self.ch[self.y][x] = ' '; self.at[self.y][x] = self.cur
        elif f == 'b':
            for _ in range(n): self.put(self.last)
        elif f == 'P':
            row = self.ch[self.y]; del row[self.x:self.x + n]; row.extend([' '] * (self.cols - len(row)))
        elif f == '@':
            row = self.ch[self.y]; row[self.x:self.x] = [' '] * n; del row[self.cols:]
        elif f == 'm':
            for v in (a or [0]):
                if v == 0 or v == 49 or (40 <= v <= 45) or v == 47 or v == 40:
                    self.cur = 0
                elif v == 7 or v == 46:
                    self.cur = 1

    def lines(self):
        return [''.join(r).rstrip() for r in self.ch]

    def cyan(self, y):
        return ''.join('#' if a else '.' for a in self.at[y])


class Session:
    def __init__(self, argv, rows=25, cols=80, term='xterm', cwd=None):
        self.screen = Screen(rows, cols)
        pid, fd = pty.fork()
        if pid == 0:
            if cwd:
                os.chdir(cwd)
            os.environ['TERM'] = term
            os.environ['LANG'] = 'C.UTF-8'
            os.environ['LC_ALL'] = 'C.UTF-8'
            os.execv(argv[0], argv)
        self.pid, self.fd = pid, fd
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        self.alive = True
        self.settle(0.6)

    def settle(self, t=0.25):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.03)
            if r:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    self.alive = False
                    return
                if not data:
                    self.alive = False
                    return
                self.screen.feed(data)
                end = max(end, time.time() + 0.08)

    def send(self, keys, t=0.25):
        os.write(self.fd, keys.encode('utf-8'))
        self.settle(t)

    def close(self):
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass

    def line(self, n):
        return self.screen.lines()[n - 1]
