"""The explosions, after the arcade burst (scattered single pixels, no solid blob): an alien (5 frames: a star, a lump, a scatter, a ring, a thin ring) and the fighter (6 frames: a flash, a fireball with pieces, the pieces fly apart and thin out). Fixed colours only
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


def scatter(c, cx, cy, n, r0, r1, letters, seed, dash=.4, gap=2.4):
    """n single pixels (design units from the centre: r0 .. r1) in the letters, no two closer than `gap` (confetti, like the arcade burst); some are a 2 pixel dash that points away from the centre."""
    rnd = random.Random(seed)
    pts = []
    for _ in range(n * 40):
        if len(pts) == n:
            break
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(r0, r1)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if all(math.hypot(x - px, y - py) >= gap for px, py in pts):
            pts.append((x, y))
            ch = rnd.choice(letters)
            c.put(x, y, ch)
            if rnd.random() < dash:
                c.put(x + math.cos(a) * c.k, y + math.sin(a) * c.k, ch)


def clump(c, cx, cy, r, letters, seed, fill=.8):
    """A dense lump of single pixels (the core of a burst)."""
    rnd = random.Random(seed)
    for py in range(c.h):
        for px in range(c.n):
            x, y = (px + .5) * c.k, (py + .5) * c.k
            if math.hypot(x - cx, y - cy) <= r and rnd.random() < fill:
                c.g[py][px] = rnd.choice(letters)


def star(c, cx, cy, arm, tip):
    """The first frame of the arcade burst: a small cross with the tips in another letter (pixels, not design units)."""
    c.put(cx, cy, 'w')
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        c.put(cx + dx * c.k, cy + dy * c.k, 'w')
        c.put(cx + dx * 2 * c.k, cy + dy * 2 * c.k, tip)
    for dx, dy in ((1, 1), (-1, -1), (1, -1), (-1, 1)):
        c.put(cx + dx * c.k, cy + dy * c.k, arm)


def alien(frame, w, h):
    """The arcade enemy burst in 5 steps: a small star, a yellow lump with white dots, a wider scatter, a ring of dots, a thin ring."""
    c = paint.Canvas(w, h)
    if frame == 'a':
        star(c, 16, 16, 'e', 'e')
    elif frame == 'b':
        clump(c, 16, 16, 4.6, 'yyyOOew', 3)
        scatter(c, 16, 16, 12, 5.5, 9.5, 'wwCwy', 5, gap=2.2)
    elif frame == 'c':
        clump(c, 16, 16, 2.6, 'yyO', 7, fill=.6)
        scatter(c, 16, 16, 30, 4.5, 11.5, 'wwwyyCw', 9)
    elif frame == 'd':
        scatter(c, 16, 16, 44, 8.5, 14.8, 'wwwwwyew', 13, gap=2.3)
    else:
        scatter(c, 16, 16, 22, 11, 15.6, 'wwwws', 17, gap=2.6)
    return c


def player(frame, w, h):
    """The fighter in 6 steps: a white flash, a fireball with pieces, then the pieces (white, blue, red) fly apart and thin out."""
    c = paint.Canvas(w, h)
    if frame == 'a':
        ball(c, 16, 16, [(2.8, 'w'), (4.6, 'C'), (5.4, 'D')], jitter=.8, seed=2)
    elif frame == 'b':
        clump(c, 16, 16, 6.2, 'wyyOOe', 4, fill=.85)
        scatter(c, 16, 16, 14, 6.5, 11.5, 'wwbbe', 21, dash=.6)
    elif frame == 'c':
        clump(c, 16, 16, 3.0, 'yyO', 6, fill=.6)
        scatter(c, 16, 16, 34, 4.5, 12.5, 'wwwbbeyO', 33, dash=.55)
    elif frame == 'd':
        scatter(c, 16, 16, 38, 8, 14.5, 'wwbbebwy', 44, dash=.5, gap=2.3)
    elif frame == 'e':
        scatter(c, 16, 16, 24, 11, 15.6, 'wwbs', 55, gap=2.5)
    else:
        scatter(c, 16, 16, 12, 12.5, 15.7, 'wws', 66, gap=3.0)
    return c


if __name__ == '__main__':
    SIZES = ((32, 32, ''), (24, 24, '.24'), (16, 16, '.16'), (12, 12, '.12'))        # the PSP, the Amiga, the terminal and the Lynx portrait, the small ports
    print(paint.write('xa', 'blue', None, alien, frames=('a', 'b', 'c', 'd', 'e'), sizes=SIZES))
    print(paint.write('xp', 'blue', None, player, frames=('a', 'b', 'c', 'd', 'e', 'f'), sizes=SIZES))
