"""The bee (zako): a blue insect with red eyes and yellow bands. Frame a: wings up, frame b: wings down. Run: python3 art/master/bee.py
All coordinates are in a design space of 32 x 32 (the PSP size); the Amiga version (24 x 24) is the same drawing."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'sprites'))
import paint  # noqa: E402

T = '0123456'


def mir(pts):
    return [(32 - x, y) for x, y in pts]


def E(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def bee(frame, size, _h=None):
    c = paint.Canvas(size)
    if frame == 'a':
        wing = [(15, 19), (11, 12), (7, 6), (3, 2), (1.5, 7), (2.5, 13), (6, 18), (11, 21)]
        vein = [(14, 18), (9, 11), (5, 5)]
    else:
        wing = [(15, 17), (10, 14.5), (5, 15.5), (2, 19), (1, 24), (4.5, 27), (9.5, 24.5), (14, 21)]
        vein = [(14, 18), (8, 19), (3, 23)]
    for pts, v in ((wing, vein), (mir(wing), mir(vein))):
        c.poly(pts, T, lo=2, hi=5, outline='0', ridge=3.0)
        for (x0, y0), (x1, y1) in zip(v, v[1:]):
            c.line(x0, y0, x1, y1, '3')
    # abdomen, tail, thorax
    ab = (16, 24, 6.2, 6.8)
    c.ellipse(*ab, T, lo=1, hi=4, outline='0')
    c.ellipse(16, 30, 2.8, 2.4, T, lo=1, hi=3, outline='0')
    c.ellipse(16, 17.5, 7.0, 4.4, T, lo=1, hi=4, outline='0')
    # yellow bands, only on the abdomen
    for y0 in (20.6, 24.6):
        c.region(lambda x, y, y0=y0: E(*ab)(x, y) and y0 <= y < y0 + 1.5, 'y', only='12345')
        c.region(lambda x, y, y0=y0: E(*ab)(x, y) and y0 + 1.5 <= y < y0 + 2.6, 'Y', only='12345')
    # head and its eyes (red, with a dark rim)
    c.ellipse(16, 10.2, 7.6, 5.8, T, lo=1, hi=5, outline='0')
    for ex in (12.4, 19.6):
        c.region(lambda x, y, ex=ex: E(ex, 10.6, 3.7, 3.9)(x, y) and not E(ex, 10.6, 2.9, 3.1)(x, y), '0', only='123456')
        c.region(E(ex, 10.6, 2.9, 3.1), 'e')
    for ex, px in ((12, 13), (19, 17)):                    # a light spot at the upper left of each eye, the pupil towards the middle
        c.put(ex - 1, 9, 'w'), c.put(ex, 9, 'w'), c.put(ex - 1, 10, 'w')
        c.put(px, 11, 'K'), c.put(px, 12, 'K'), c.put(px + 1, 11, 'K'), c.put(px + 1, 12, 'K')
    # antennae
    for sgn in (1, -1):
        def X(x):
            return x if sgn == 1 else 31 - x
        c.line(X(13), 5, X(10), 2, 'y')
        for yy in (1, 2):
            c.put(X(9), yy, 'y'), c.put(X(8), yy, 'y')
    return c


if __name__ == '__main__':
    print(paint.write('bee', 'blue', None, bee))
