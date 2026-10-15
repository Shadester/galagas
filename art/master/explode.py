"""The explosions: an alien (3 frames: a flash, a fireball, sparks) and the fighter (4 frames: a white flash, a fireball with debris, a ring with debris, debris). Fixed colours only
(white, yellow, orange, red, cyan, blue): the same in every palette. Design space 32 x 32, drawn at 32 and at 24 pixels. Run: python3 art/master/explode.py"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'sprites'))
import paint  # noqa: E402


def ball(c, cx, cy, layers, jitter=1.0, seed=1, spokes=0, spoke_len=0, spoke_ch='y'):
    """layers: [(radius, letter)] from the inside out; the edge is rough by `jitter` (an angle noise)."""
    rnd = random.Random(seed)
    noise = [rnd.uniform(-1, 1) for _ in range(24)]

    def rough(a):
        i = (a % (2 * math.pi)) / (2 * math.pi) * 24
        f = i - int(i)
        return (noise[int(i) % 24] * (1 - f) + noise[(int(i) + 1) % 24] * f) * jitter

    def paint_pixel(x, y):
        dx, dy = x - cx, y - cy
        r = math.hypot(dx, dy)
        a = math.atan2(dy, dx)
        rr = r - rough(a)
        for rad, ch in layers:
            if rr < rad:
                return ch
        if spokes:
            ang = (a % (2 * math.pi)) / (2 * math.pi) * spokes
            if abs(ang - round(ang)) < .12 and r < spoke_len:
                return spoke_ch
        return None
    c.region(lambda x, y: paint_pixel(x, y) is not None, 'w')
    for py in range(c.h):
        for px in range(c.n):
            ch = paint_pixel((px + .5) * c.k, (py + .5) * c.k)
            if ch:
                c.g[py][px] = ch


def sparks(c, cx, cy, n, r0, r1, letters, seed):
    rnd = random.Random(seed)
    for _ in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(r0, r1)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        ch = rnd.choice(letters)
        c.put(x, y, ch)
        if rnd.random() < .5:
            c.put(x + 1.4, y, ch)


def alien(frame, w, h):
    c = paint.Canvas(w, h)
    if frame == 'a':
        ball(c, 16, 16, [(2.6, 'w'), (4.4, 'y'), (6.0, 'O'), (7.0, 'P')], jitter=.9, seed=3)
    elif frame == 'b':
        ball(c, 16, 16, [(4.2, 'w'), (7.2, 'y'), (10.0, 'O'), (12.0, 'e'), (13.2, 'P')], jitter=1.6, seed=5, spokes=8, spoke_len=15.5)
    else:
        ball(c, 16, 16, [(3, 'P')], jitter=1.0, seed=7)
        sparks(c, 16, 16, 18, 6, 15, 'yyOOeP', 11)
        c.region(lambda x, y: 13 <= math.hypot(x - 16, y - 16) <= 14.2 and math.sin(math.atan2(y - 16, x - 16) * 5) > .5, 'P')
    return c


def player(frame, w, h):
    c = paint.Canvas(w, h)
    if frame == 'a':
        ball(c, 16, 16, [(4, 'w'), (6.5, 'C'), (7.6, 'D')], jitter=.8, seed=2)
    elif frame == 'b':
        ball(c, 16, 16, [(4.5, 'w'), (7.5, 'y'), (10.5, 'O'), (12.4, 'e'), (13.4, 'P')], jitter=1.7, seed=4, spokes=10, spoke_len=15.5, spoke_ch='w')
        sparks(c, 16, 16, 10, 8, 15, 'wbwb', 21)
    elif frame == 'c':
        ball(c, 16, 16, [(3.2, 'y'), (5.2, 'O'), (6.4, 'P')], jitter=1.2, seed=6)
        c.region(lambda x, y: 11.5 <= math.hypot(x - 16, y - 16) <= 13.6, 'O', only='.')
        c.region(lambda x, y: 12.8 <= math.hypot(x - 16, y - 16) <= 13.6, 'P', only='O')
        sparks(c, 16, 16, 16, 8, 15.5, 'wwbyc', 33)
    else:
        sparks(c, 16, 16, 24, 5, 15.5, 'wwbycOe', 44)
        ball(c, 16, 16, [(1.6, 'P')], jitter=.3, seed=9)
    return c


if __name__ == '__main__':
    print(paint.write('xa', 'blue', None, alien, frames=('a', 'b', 'c')))
    print(paint.write('xp', 'blue', None, player, frames=('a', 'b', 'c', 'd')))
