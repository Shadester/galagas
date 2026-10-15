"""The butterfly (goei): a red butterfly with a blue body. Frame a: wings open, frame b: wings raised. Run: python3 art/master/bfly.py (design space 32 x 32)"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'sprites'))
import paint  # noqa: E402

R = '0123456'       # red
B = 'hijklmn'       # blue (the secondary ramp)


def mir(pts):
    return [(32 - x, y) for x, y in pts]


def E(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def bfly(frame, size, _h=None):
    c = paint.Canvas(size)
    if frame == 'a':
        up = [(14, 13), (9, 7), (3, 4), (0.8, 8.5), (1.5, 15), (6, 19.5), (13, 19.5)]
        low = [(14, 19), (8, 20), (4, 24.5), (6, 29), (11, 28.5), (14, 24)]
        spots = [(5, 10), (4, 15)]
    else:
        up = [(14, 14), (11.5, 7), (8, 2), (4.5, 5), (4.5, 12), (8, 18.5), (13, 21)]
        low = [(14, 20), (10, 22), (8, 26.5), (11, 29), (14, 25)]
        spots = [(7, 8), (7, 12)]
    for w in (low, up):
        for pts in (w, mir(w)):
            c.poly(pts, R, lo=1, hi=5, outline='0', ridge=3.2)
    for sx, sy in spots:                                   # yellow spots on the wings
        for x in (sx, 30 - sx):
            c.region(lambda X, Y, x=x, sy=sy: x <= X < x + 2.2 and sy <= Y < sy + 2.2, 'y', only='0123456')
            c.region(lambda X, Y, x=x, sy=sy: x + 1.1 <= X < x + 2.2 and sy + 1.1 <= Y < sy + 2.2, 'Y', only='y')
    # body, head, eyes, antennae
    c.ellipse(16, 20, 2.9, 8.6, B, lo=1, hi=5, outline='h')
    c.ellipse(16, 9.5, 4.6, 4.2, B, lo=1, hi=6, outline='h')
    for ex in (14.1, 17.9):
        c.region(E(ex, 9.8, 1.9, 2.1), 'K')
    c.put(13, 8, 'w'), c.put(17, 8, 'w')
    for sgn in (1, -1):
        def X(x):
            return x if sgn == 1 else 31 - x
        c.line(X(14), 6, X(11), 2, 'y')
        c.put(X(10), 1, 'y'), c.put(X(10), 2, 'y'), c.put(X(11), 1, 'y')
    return c


if __name__ == '__main__':
    print(paint.write('bfly', 'red', 'blue', bfly))
