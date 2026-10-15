"""The fighter: a white ship with blue wings, red wing tips and a cyan cockpit. It is a hardware sprite on the Amiga (16 pixels wide, 15 colours: only the tones 1, 3, 5 of the blue and red
ramps and the greys, whites, cyan and yellow of the palette entries 17 .. 31), so the drawing uses only those. Design space 32 x 40; the sizes: 24 x 30 (PSP), 16 x 20 (Amiga).
Run: python3 art/master/ship.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'sprites'))
import paint  # noqa: E402

BLUE = '1133355'     # tones 1, 3, 5 of the blue ramp only
WHITE = 'ssSSwww'


def mir(pts):
    return [(32 - x, y) for x, y in pts]


def E(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def ship(frame, w, h):
    c = paint.Canvas(w, h)
    wing = [(13, 21), (8, 22.5), (2.5, 28), (0.4, 38), (5, 38), (9, 35.5), (13, 31)]
    for pts in (wing, mir(wing)):
        c.poly(pts, BLUE, lo=0, hi=6, outline='1', ridge=3.5)
    for side in (lambda x: x, lambda x: 32 - x):                   # red tips of the wings
        c.region(lambda x, y, side=side: side(x) < 4.6 and y > 32, 'k', only='135')
    body = [(16, 0.4), (19.6, 10), (19.9, 31), (18, 38.5), (14, 38.5), (12.1, 31), (12.4, 10)]
    c.poly(body, WHITE, lo=0, hi=6, ridge=4.0)
    c.ellipse(16, 15.5, 2.3, 3.8, 'DDCCCCC', lo=0, hi=6)                                  # the cockpit
    c.put(15, 13, 'w')
    c.region(lambda x, y: 14.8 <= x < 17.2 and 24.5 <= y < 31, 'm', only='sSw')           # a red stripe
    for gx in (9.2, 21.2):                                                                # the cannons
        c.region(lambda x, y, gx=gx: gx <= x < gx + 1.8 and 21 <= y < 29, 'S', only=None)
        c.region(lambda x, y, gx=gx: gx <= x < gx + 1.8 and 29 <= y < 30.6, 'k', only='S')
    c.region(lambda x, y: 14 <= x < 18 and 38 <= y < 40, 'y')                             # the glow of the engine
    return c


if __name__ == '__main__':
    print(paint.write('ship', 'blue', 'red', ship, frames=('a',), sizes=((24, 30, ''), (16, 20, '.16'))))
