#!/usr/bin/env python3
"""Record docs/gameplay.gif: the program runs in a pseudo-terminal (--autoplay), the screen is read with pyte and drawn cell by cell.
Needs Pillow and pyte (pip install pillow pyte). Usage: python3 tools/make_gif.py [cols rows seconds [blocks|octants [landscape]]]
The default is the portrait field (the program's own default) with octant characters in an 85 x 57 window (a canvas of 170 x 217 pixels):
the octant cells are drawn as their 2 x 4 pixels, so the picture has 4 times the pixels of half blocks. `blocks` records half blocks
(a window of at least 51 x 35 for the portrait field), `landscape` the C64's field (80 x 27 with blocks, 160 x 52 with octants)."""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

import re

import pyte
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(HERE, '..', 'target', 'release', 'galaga-tui')
LANDSCAPE = 'landscape' in sys.argv[1:]
MODE = 'blocks' if 'blocks' in sys.argv[1:] else 'octants'
NUMS = [a for a in sys.argv[1:] if a.isdigit()]
DEFAULT = (['80', '27', '30'] if MODE == 'blocks' else ['160', '52', '30']) if LANDSCAPE else (['51', '35', '30'] if MODE == 'blocks' else ['85', '57', '30'])
COLS, ROWS, SECONDS = (int(v) for v in NUMS + DEFAULT[len(NUMS):])
CW, CH, FPS = 6, 12, 10

# the octant characters: the character -> the pattern of its 2 x 4 pixels (bit i = octant i + 1: 1 2 / 3 4 / 5 6 / 7 8), from src/octant.rs
OCT = {chr(int(h, 16)) if len(h) > 1 else h: i for i, h in enumerate(re.findall(r"'(?:\\u\{([0-9a-f]+)\}| )'", open(os.path.join(HERE, '..', 'src', 'octant.rs')).read()))}
OCT[' '] = 0


def font():
    for p in ('/System/Library/Fonts/Menlo.ttc', '/System/Library/Fonts/Monaco.ttf', '/Library/Fonts/Arial Unicode.ttf', '/usr/share/fonts/TTF/DejaVuSansMono.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, 10)
    return ImageFont.load_default()


def color(h, default):
    if not h or h == 'default':
        return default
    try:
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return default


def picture(screen, fnt):
    img = Image.new('RGB', (COLS * CW, ROWS * CH))
    d = ImageDraw.Draw(img)
    for y in range(ROWS):
        for x in range(COLS):
            c = screen.buffer[y][x]
            fg, bg = color(c.fg, (255, 255, 255)), color(c.bg, (0, 0, 0))
            if c.data in OCT and c.data != ' ':
                mask = OCT[c.data]
                for i in range(8):
                    px, py = x * CW + (i % 2) * (CW // 2), y * CH + (i // 2) * (CH // 4)
                    d.rectangle([px, py, px + CW // 2 - 1, py + CH // 4 - 1], fill=fg if mask >> i & 1 else bg)
            elif c.data == '▀':
                d.rectangle([x * CW, y * CH, x * CW + CW - 1, y * CH + CH // 2 - 1], fill=fg)
                d.rectangle([x * CW, y * CH + CH // 2, x * CW + CW - 1, y * CH + CH - 1], fill=bg)
            else:
                d.rectangle([x * CW, y * CH, x * CW + CW - 1, y * CH + CH - 1], fill=bg)
                if c.data.strip():
                    d.text((x * CW, y * CH - 1), c.data, fill=fg, font=fnt)
    return img


pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM='xterm-256color', COLORTERM='truecolor')
    os.execv(EXE, [EXE, '--no-save', '--autoplay', '--' + MODE] + (['--landscape'] if LANDSCAPE else []))
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLS, 0, 0))
screen = pyte.Screen(COLS, ROWS)
stream = pyte.ByteStream(screen)
fnt = font()
frames, t0, n = [], time.time(), 0
while n < SECONDS * FPS:
    end = t0 + n / FPS
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.01)
        if r:
            d = os.read(fd, 65536)
            if b'\x1b[c' in d:
                os.write(fd, b'\x1b[?62;c')
            stream.feed(d)
    if n >= 5:                                   # the first half second is the start-up
        frames.append(picture(screen, fnt))
    n += 1
os.close(fd)
os.kill(pid, signal.SIGKILL)
os.waitpid(pid, 0)
out = os.path.join(HERE, '..', 'docs', 'gameplay.gif')
os.makedirs(os.path.dirname(out), exist_ok=True)
frames[0].save(out, save_all=True, append_images=frames[1:], duration=1000 // FPS, loop=0, optimize=True)
print(len(frames), 'frames,', os.path.getsize(out) // 1024, 'KB')
