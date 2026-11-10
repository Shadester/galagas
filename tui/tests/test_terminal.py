#!/usr/bin/env python3
"""Runs the release binary in a pseudo-terminal and checks what a terminal sees: the game starts and draws, Q leaves from the title screen
and gives the terminal back, a small window gets a message, a resize draws again, the kitty keyboard protocol is switched on and off.
Usage: python3 tests/test_terminal.py   (stdlib only; builds the program first)"""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(HERE, '..', 'target', 'release', 'galaga-tui')
subprocess.run(['cargo', 'build', '--release', '-q'], cwd=os.path.join(HERE, '..'), check=True)


class Pty:
    def __init__(self, rows, cols, *args, kitty=False, term='xterm-256color', px=(0, 0), portrait=False):
        self.kitty, self.buf, self.px = kitty, b'', px
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            for k in ('TMUX', 'KITTY_WINDOW_ID', 'TERM_PROGRAM', 'GHOSTTY_RESOURCES_DIR'):
                os.environ.pop(k, None)
            os.environ.update(TERM=term, COLORTERM='truecolor')
            os.execv(EXE, [EXE, '--no-save', *args] + ([] if portrait else ['--landscape']))   # the tests of the landscape field are the older ones
        self.resize(rows, cols)

    def resize(self, rows, cols, px=None):
        self.px = px or self.px
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, *self.px))
        os.kill(self.pid, signal.SIGWINCH)

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    d = os.read(self.fd, 65536)
                except OSError:
                    return
                if b'\x1b[c' in d:        # the program asks which keyboard protocol we have
                    os.write(self.fd, (b'\x1b[?0u' if self.kitty else b'') + b'\x1b[?62;c')
                self.buf += d

    def send(self, data, wait=0.3):
        os.write(self.fd, data)
        self.pump(wait)

    def exited(self):
        try:
            p, st = os.waitpid(self.pid, os.WNOHANG)
        except ChildProcessError:
            return True
        return bool(p) and os.WEXITSTATUS(st) == 0

    def close(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.close(self.fd)
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass


bad = 0


def check(name, ok):
    global bad
    print(('PASS ' if ok else 'FAIL ') + name)
    bad += not ok


p = Pty(30, 90)
p.pump(1.0)
check('draws the title screen (half blocks, 24-bit colour)', '▀'.encode() in p.buf and b'\x1b[38;2;' in p.buf)
check('uses the alternate screen and hides the cursor', b'\x1b[?1049h' in p.buf and b'\x1b[?25l' in p.buf)
p.send(b'q', 1.0)
check('Q on the title screen leaves and gives the terminal back', p.exited() and b'\x1b[?1049l' in p.buf and b'\x1b[?25h' in p.buf)
p.close()

for key, name in ((b'\x03', 'Ctrl-C'), (b'\x1b', 'Esc')):
    p = Pty(30, 90)
    p.pump(1.0)
    p.send(key, 1.0)
    check(name + ' leaves', p.exited() and b'\x1b[?1049l' in p.buf)
    p.close()

p = Pty(30, 90, '--autoplay')
p.pump(1.5)
p.buf = b''
p.resize(20, 70)
p.pump(1.0)
check('a small window gets a message', b'Please make the window' in p.buf)
p.buf = b''
p.resize(56, 170)
p.pump(1.0)
check('a big window is drawn again', len(p.buf) > 20000)
p.close()

# a window that goes full screen or is tiled sends a burst of resizes: the last size is the one that counts, also when keys come in the same batch
p = Pty(30, 90, '--autoplay')
p.pump(1.0)
p.buf = b''
for rows, cols in ((20, 70), (40, 120), (24, 80), (50, 150), (56, 170)):
    p.resize(rows, cols)
os.write(p.fd, b'z')                       # a key behind the resizes, in the same batch
p.pump(1.5)
check('a burst of resizes: the picture is drawn for the last size (rows 50 to 56 are written)', b'\x1b[55;' in p.buf or b'\x1b[56;' in p.buf)
p.close()

p = Pty(30, 90, kitty=True)
p.pump(1.0)
check('the kitty keyboard flags are pushed', b'\x1b[>' in p.buf)
p.send(b'\x1b[32u')
p.send(b'\x1b[32;1:3u')       # space down and up: starts the game
p.send(b'\x1b[97u', 0.5)
p.send(b'\x1b[97;1:3u')       # A down and up
p.send(b'\x1b[113u')
p.send(b'\x1b[113;1:3u')      # Q: back to the title
p.send(b'\x1b[113u', 0.5)     # Q: leave
check('with key releases: plays, leaves, pops the flags', p.exited() and b'\x1b[<1u' in p.buf)
p.close()

# the portrait field (the default): tall and narrow, 51 x 35 cells at the least
p = Pty(40, 60, portrait=True)
p.pump(1.0)
check('portrait: drawn with half blocks in a 60 x 40 window', '▀'.encode() in p.buf and b'make the window' not in p.buf)
p.buf = b''
p.resize(30, 90)
p.pump(1.0)
check('portrait: a window of 90 x 30 is too small (51 x 35 at least)', b'at least 51 x 35' in p.buf)
p.send(b'q', 1.0)
check('portrait: Q on the title screen leaves', p.exited())
p.close()

p = Pty(60, 80, '--autoplay', portrait=True)
p.pump(2.0)
check('portrait: autoplay runs', '▀'.encode() in p.buf and len(p.buf) > 20000)
p.close()

p = Pty(40, 100, term='xterm-kitty', px=(800, 800), portrait=True)    # 8 x 20 pixels a cell
p.pump(1.5)
check('portrait in kitty: an image (a canvas of 204 x 260 game pixels, 2 x 3 or more)', b'\x1b_Ga=T,f=24,s=' in p.buf)
p.close()

# the pixel mode: the picture is an image of the kitty graphics protocol (kitty, Ghostty), when the terminal tells the size of its cells
p = Pty(40, 100, term='xterm-kitty', px=(800, 640))
p.pump(1.5)
check('kitty: the picture is an image (800 x 500 pixels, zlib)', b'\x1b_Ga=T,f=24,s=800,v=500,o=z,i=' in p.buf and b'p=1,q=2,C=1,z=-1073741825,m=' in p.buf)
check('kitty: no half blocks, no octants in the play area', '▀'.encode() not in p.buf and sum(p.buf.count(chr(c).encode()) for c in range(0x1CD00, 0x1CDE6)) == 0)
check('kitty: the next picture is a new image (id 2) and the old one is deleted after it (no flash)', b'o=z,i=2,' in p.buf and b'\x1b_Ga=d,d=I,i=1,q=2' in p.buf)
p.buf = b''
p.resize(56, 170, px=(1700, 1120))
p.pump(1.0)
check('kitty: a resize deletes the images and sends a bigger one (1680 x 1050)', b'\x1b_Ga=d,d=A' in p.buf and b's=1680,v=1050' in p.buf)
p.buf = b''
p.resize(14, 50, px=(500, 280))
p.pump(1.0)
check('kitty: a window too small for everything gets a message and no image', b'make the window' in p.buf and b'\x1b_Ga=T' not in p.buf)
p.buf = b''
p.resize(40, 100, px=(800, 640))
p.pump(1.0)
p.send(b'q', 1.0)
check('kitty: leaving deletes the image first', p.exited() and b'\x1b_Ga=d,d=A' in p.buf and p.buf.rfind(b'\x1b_Ga=d,d=A') < p.buf.rfind(b'\x1b[?1049l'))
p.close()

p = Pty(40, 100, '--blocks', term='xterm-kitty', px=(800, 640))
p.pump(1.0)
check('--blocks in kitty: half blocks, no image', '▀'.encode() in p.buf and b'\x1b_G' not in p.buf)
p.close()

p = Pty(40, 100, '--octants', term='xterm-kitty', px=(800, 640))
p.pump(1.0)
check('--octants in kitty: octants, no image', b'\x1b_G' not in p.buf and sum(p.buf.count(chr(c).encode()) for c in range(0x1CD00, 0x1CDE6)) > 500)
p.close()

p = Pty(40, 100, '--pixels', px=(800, 640))
p.pump(1.0)
check('--pixels forces the image in another terminal', b'\x1b_Ga=T' in p.buf)
p.close()

# the octant mode: cells of 2 x 4 pixels (Unicode 16 octant characters), with --octants, and in kitty when it does not tell the size of its cells
OCT = [chr(c).encode() for c in range(0x1CD00, 0x1CDE6)]
def octants(buf):
    return sum(buf.count(o) for o in OCT)

p = Pty(56, 170, term='xterm-kitty')
p.pump(1.5)
check('kitty without cell sizes: the play area is drawn with octant characters', octants(p.buf) > 1000)
check('kitty without cell sizes: no kitty graphics commands', b'\x1b_G' not in p.buf)
p.buf = b''
p.resize(20, 70)
p.pump(1.0)
check('kitty without cell sizes: a small window gets a message', b'make the window' in p.buf)
p.buf = b''
p.resize(40, 100)
p.pump(1.0)
check('kitty without cell sizes: a smaller window is drawn again with octants', octants(p.buf) > 500)
p.close()


p = Pty(40, 100, '--octants')
p.pump(1.0)
check('--octants forces the octants in another terminal', octants(p.buf) > 500)
p.close()

p = Pty(40, 100, '--octants', '--blocks')
p.pump(1.0)
check('--blocks wins over --octants', octants(p.buf) == 0)
p.close()

sys.exit(1 if bad else 0)
