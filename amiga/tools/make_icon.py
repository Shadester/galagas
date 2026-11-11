#!/usr/bin/env python3
"""Make Workbench icons (.info, the classic format that every Workbench reads: 2 bitplanes, 4 colours) with the fighter of the game.
Usage: make_icon.py OUT.info KIND [TOOLTYPE ...] [--tool DEFAULTTOOL] [--stack N]
KIND: drawer, tool (a program) or project (a file that DEFAULTTOOL opens, the Slave for WHDLoad)."""
import struct
import sys

SHIP = ["       ##       ", "      #WW#      ", "      #WW#      ", "      #WW#      ", "  #   #BB#   #  ", " #R#  #WW#  #R# ",
        " #R# ##WW## #R# ", " #RB#WWWWWW#BR# ", " #RBWWWBBWWWBR# ", " #RRWWWWWWWWRR# ", " ##RR##WW##RR## ", "  ###  ##  ###  "]
PIX = {' ': 0, '#': 1, 'W': 2, 'B': 3, 'R': 3}        # the Workbench palette: grey, black, white, blue (the red wings are blue: only 4 colours)
KIND = {'drawer': 2, 'tool': 3, 'project': 4}
# the window of a drawer icon (NewWindow + the position), the pointers are 0
DRAWER = bytes.fromhex('00570047009500aaffff000000000200127f' + '00000000' * 5 + '005e0044ffffffff0001' + '00000000' * 2)


def image(w=40, h=26):
    """planar data of the picture (a ship doubled in size, centred), 2 planes"""
    pix = [[0] * w for _ in range(h)]
    for y, row in enumerate(SHIP):
        for x, c in enumerate(row):
            for dy in (0, 1):
                for dx in (0, 1):
                    pix[1 + 2 * y + dy][4 + 2 * x + dx] = PIX[c]
    ww = (w + 15) // 16 * 2
    planes = b''
    for p in (0, 1):
        for row in pix:
            bits = ''.join(str((c >> p) & 1) for c in row).ljust(ww * 8, '0')
            planes += int(bits, 2).to_bytes(ww, 'big')
    return w, h, planes


def icon(kind, tooltypes, tool, stack):
    w, h, planes = image()
    dobj = struct.pack('>HHIhhHHHHHIIIIIHI', 0xe310, 1, 0, 0, 0, w, h, 5, 1, 1, 1, 0, 0, 0, 0, 0, 1)
    dobj += struct.pack('>BBIIiiIII', KIND[kind], 0, 1 if tool else 0, 1 if tooltypes else 0, -2**31, -2**31, 1 if kind == 'drawer' else 0, 0, stack)
    out = dobj + (DRAWER if kind == 'drawer' else b'')
    out += struct.pack('>hhHHHIBBI', 0, 0, w, h, 2, 1, 3, 0, 0) + planes
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
