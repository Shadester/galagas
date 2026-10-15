#!/usr/bin/env python3
"""A preview sheet of a creature: for each frame the 32 x 32 master (PSP) enlarged, the 24 x 24 AGA version, the 24 x 24 OCS version (both enlarged), and the three at the real size on black.
Usage: python3 tools/sprites/preview.py NAME [out.png] [--variant KEY=...]"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master  # noqa: E402
import reduce  # noqa: E402

art = master.art


def paint(im, rows, x0, y0, scale, cols=None):
    cols = cols or art.COLOURS64
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != '.':
                c = cols[art.PEN[ch]]
                for dy in range(scale):
                    for dx in range(scale):
                        im.putpixel((x0 + x * scale + dx, y0 + y * scale + dy), c)


def versions(rows, aga):
    """the 32 x 32 master, the 24 x 24 AGA drawing (the same script at 24 pixels) and its OCS version (4 tones for each ramp)"""
    return rows, aga, reduce.to_ocs(aga)


def sheet(name, out=None):
    primary, secondary, frames = master.load(name)
    frames24 = master.load(name, '.24')[2]
    n = len(frames)
    W, H = 20 + n * (32 * 8 + 24 * 10 * 2 + 60), 24 * 10 + 140
    im = Image.new('RGB', (W, H), (14, 14, 24))
    x = 10
    for f, rows in frames.items():
        m, aga, ocs = versions(rows, frames24[f])
        paint(im, m, x, 10, 8)
        paint(im, aga, x + 32 * 8 + 20, 10, 10)
        paint(im, ocs, x + 32 * 8 + 20 + 24 * 10 + 20, 10, 10)
        # at the real size, a few times
        for i, (r, s) in enumerate(((m, 1), (aga, 1), (ocs, 1))):
            paint(im, r, x + 10 + i * 50, 24 * 10 + 40, 2)
        x += 32 * 8 + 24 * 10 * 2 + 60
    path = out or os.path.join(os.environ.get('TMPDIR', '/tmp'), f'sprite_{name}.png')
    im.save(path)
    print(path)


if __name__ == '__main__':
    sheet(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
