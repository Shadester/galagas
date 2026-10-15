"""The boss Galaga: a big green insect with cyan horns, angular wings and angry yellow eyes. Frame a: wings spread, frame b: wings folded in. The hit boss is the same art in purple
(made by the generators). Run: python3 art/master/boss.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'sprites'))
import paint  # noqa: E402

G = '0123456'


def mir(pts):
    return [(32 - x, y) for x, y in pts]


def E(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def boss(frame, size, _h=None):
    c = paint.Canvas(size)
    if frame == 'a':
        wing = [(13, 14), (7, 12.5), (1.5, 16), (0.7, 23), (3, 29), (7.5, 30.5), (10.5, 25), (13, 21)]
        seam = [(12, 16), (6, 17), (3, 22)]
    else:
        wing = [(13, 14), (8, 13), (4, 16), (3.5, 23), (5.5, 29), (9, 30), (11, 25), (13, 21)]
        seam = [(12, 16), (8, 18), (6, 23)]
    for pts, sm in ((wing, seam), (mir(wing), mir(seam))):
        c.poly(pts, G, lo=1, hi=5, outline='0', ridge=3.0)
        for (x0, y0), (x1, y1) in zip(sm, sm[1:]):
            c.line(round(x0), round(y0), round(x1), round(y1), '1')
    # abdomen with yellow stripes
    ab = (16, 23, 5.6, 7.4)
    c.ellipse(*ab, G, lo=1, hi=5, outline='0')
    for y in (20.8, 24.8):
        c.region(lambda x, yy, y=y: E(*ab)(x, yy) and y <= yy < y + 1.4, 'y', only='12345')
    # horns (cyan), then the head
    horn = [(10.5, 8), (7, 5.5), (5, 1.5), (9.5, 3.5), (12.5, 6)]
    for pts in (horn, mir(horn)):
        c.poly(pts, 'DDDCCCC', lo=2, hi=6, outline='D', ridge=1.5)
    c.poly([(14.5, 6.5), (16, 0.5), (17.5, 6.5)], 'DDDCCCC', lo=2, hi=6, outline='D', ridge=1.5)
    c.ellipse(16, 12, 8.3, 6.4, G, lo=1, hi=6, outline='0')
    # angry yellow eyes: slanted, with a dark pupil and a light spot
    for pts in ([(8.5, 9.5), (14, 11.5), (14, 15), (9.5, 14.5)], [(23.5, 9.5), (18, 11.5), (18, 15), (22.5, 14.5)]):
        c.poly(pts, 'KKKyyyy', flat=5, outline='0')
    for px in (12, 18):
        c.put(px, 13, 'K'), c.put(px, 14, 'K'), c.put(px + (1 if px == 12 else -1), 13, 'K')
    c.put(10, 12, 'w'), c.put(21, 12, 'w')
    # mandibles
    for x0 in (13, 18):
        c.put(x0, 17, 'w'), c.put(x0 + 1, 17, 'w'), c.put(x0 + (1 if x0 == 13 else 0), 18, 'w')
    return c


if __name__ == '__main__':
    print(paint.write('boss', 'green', None, boss))
