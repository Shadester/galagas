"""Reducing art: `reduce_rows` (the small lives icon) and `to_ocs`: the AGA drawing with the 7 tones of a ramp mapped to 4 (deep, dark, mid, light) for the OCS palette."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master  # noqa: E402

art = master.art
OCS_TONE = {0: 0, 1: 1, 2: 1, 3: 3, 4: 3, 5: 5, 6: 5}               # AGA tone -> OCS tone (the letters of the ramp: deep, dark, mid, light)


def reduce_rows(rows, dw, dh):
    """Every output pixel takes the palette letter that covers most of its source area (transparent when most of it is empty)."""
    sh, sw = len(rows), len(rows[0])
    kx, ky = sw / dw, sh / dh
    out = []
    for y in range(dh):
        row = ''
        for x in range(dw):
            x0, x1, y0, y1 = x * kx, (x + 1) * kx, y * ky, (y + 1) * ky
            cover = {}
            for sy in range(int(y0), min(sh, int(y1 + .999))):
                for sx in range(int(x0), min(sw, int(x1 + .999))):
                    w = (min(x1, sx + 1) - max(x0, sx)) * (min(y1, sy + 1) - max(y0, sy))
                    cover[rows[sy][sx]] = cover.get(rows[sy][sx], 0) + w
            empty = cover.pop('.', 0)
            total = empty + sum(cover.values())
            row += '.' if (not cover or empty > total * .5) else max(cover.items(), key=lambda kv: kv[1])[0]
        out.append(row)
    return out


def to_ocs(rows):
    """AGA letters -> OCS letters (the extra tones are not in the OCS palette)."""
    table = {}
    for ramp, letters in art.TONE.items():
        for t, ch in enumerate(letters):
            table[ch] = letters[OCS_TONE[t]]
    return master.recolour(rows, table)
