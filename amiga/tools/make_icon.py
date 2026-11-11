#!/usr/bin/env python3
"""Make Workbench icons (.info, the classic format that every Workbench reads: 2 bitplanes, 4 colours) with the fighter of the game.
Usage: make_icon.py OUT.info KIND [TOOLTYPE ...] [--tool DEFAULTTOOL] [--stack N]
KIND: drawer, tool (a program) or project (a file that DEFAULTTOOL opens, the Slave for WHDLoad)."""
import struct
import sys

SHIP = ["       WW       ", "      WWWW      ", "      WWWW      ", "  B   WBBW   B  ", " BB   WWWW   BB ", " BBB WWWWWW BBB ",
        " BBBWWWBBWWWBBB ", " BBBWWWWWWWWBBB ", " BB  WW  WW  BB ", "  B  W    W  B  "]
BEE = ["B BBBB B", " BWBBWB ", "BBBBBBBB", " BBBBBB ", "  BBBB  ", " B BB B ", "B      B"]
PIX = {' ': 1, 'W': 2, 'B': 3}       # the Workbench palette: 0 grey, 1 black, 2 white, 3 blue
STARS = [(5, 4), (55, 6), (9, 20), (58, 24), (3, 34), (60, 40), (22, 3), (44, 18), (52, 36), (14, 41)]
KIND = {'drawer': 2, 'tool': 3, 'project': 4}
# the window of a drawer icon (NewWindow + the position), the pointers are 0
DRAWER = bytes.fromhex('00570047009500aaffff000000000200127f' + '00000000' * 5 + '005e0044ffffffff0001' + '00000000' * 2)


def image(selected, w=64, h=44):
    """planar data of the picture: the bee over the fighter (doubled in size) in space, 2 planes. Selected: black and blue change places."""
    pix = [[1] * w for _ in range(h)]
    for x, y in STARS:
        pix[y][x] = 2
    for art, x0, y0 in ((BEE, 24, 3), (SHIP, 16, 20)):
        for y, row in enumerate(art):
            for x, c in enumerate(row):
                if c != ' ' or art is SHIP:
                    for dy in (0, 1):
                        for dx in (0, 1):
                            pix[y0 + 2 * y + dy][x0 + 2 * x + dx] = PIX[c]
    if selected:
        pix = [[{1: 3, 3: 1}.get(c, c) for c in row] for row in pix]
    ww = (w + 15) // 16 * 2
    planes = b''
    for p in (0, 1):
        for row in pix:
            bits = ''.join(str((c >> p) & 1) for c in row).ljust(ww * 8, '0')
            planes += int(bits, 2).to_bytes(ww, 'big')
    return w, h, planes


def icon(kind, tooltypes, tool, stack):
    w, h, planes = image(False)
    _, _, planes2 = image(True)
    dobj = struct.pack('>HHIhhHHHHHIIIIIHI', 0xe310, 1, 0, 0, 0, w, h, 6, 1, 1, 1, 1, 0, 0, 0, 0, 1)
    dobj += struct.pack('>BBIIiiIII', KIND[kind], 0, 1 if tool else 0, 1 if tooltypes else 0, -2**31, -2**31, 1 if kind == 'drawer' else 0, 0, stack)
    out = dobj + (DRAWER if kind == 'drawer' else b'')
    out += struct.pack('>hhHHHIBBI', 0, 0, w, h, 2, 1, 3, 0, 0) + planes     # the picture, and the one for a selected icon
    out += struct.pack('>hhHHHIBBI', 0, 0, w, h, 2, 1, 3, 0, 0) + planes2
    if tool:
        out += struct.pack('>I', len(tool) + 1) + tool.encode() + b'\0'
    if tooltypes:
        out += struct.pack('>I', (len(tooltypes) + 1) * 4)
        for t in tooltypes:
            out += struct.pack('>I', len(t) + 1) + t.encode() + b'\0'
    return out


if __name__ == '__main__':
    a = sys.argv[1:]
    stack = int(a[a.index('--stack') + 1]) if '--stack' in a else 4096
    tool = a[a.index('--tool') + 1] if '--tool' in a else ''
    rest = [x for i, x in enumerate(a) if x not in ('--tool', '--stack') and (i == 0 or a[i - 1] not in ('--tool', '--stack'))]
    open(rest[0], 'wb').write(icon(rest[1], rest[2:], tool, stack))
