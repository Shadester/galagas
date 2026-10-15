"""A small painter for the master art (32 x 32): shapes with lit tones and outlines, drawn by a script per creature (art/master/NAME.py), written as art/master/NAME.txt.
Light comes from the upper left. A shape has a height (a dome: a hemisphere for an ellipse, a ridge for a wing), the tone follows the slope against the light.
Pixels are letters of the master alphabet (see master.py): digits = primary ramp tone 0 .. 6, a .. g = secondary ramp, and the fixed letters."""
import math
import os

LIGHT = (-0.55, -0.65, 0.52)
_n = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _n for v in LIGHT)
N = 32


class Canvas:
    """size: the pixels of the picture (32: PSP, 24: Amiga). Everything is drawn in a design space of 32 x 32: the shapes are the same at every size, only the pixels differ."""

    def __init__(self, size=32, height=None):
        self.n = size                                         # the width in pixels
        self.h = height or size                               # the height in pixels
        self.k = 32.0 / size                                  # design units a pixel (the design is 32 units wide)
        self.g = [['.'] * size for _ in range(self.h)]

    def at(self, x, y):                                       # (a pixel of the picture)
        return self.g[y][x] if 0 <= x < self.n and 0 <= y < self.h else '.'

    def put(self, x, y, ch):
        """A pixel at design coordinates (x, y: 0 .. 31)."""
        px, py = int(x / self.k), int(y / self.k)
        if 0 <= px < self.n and 0 <= py < self.h:
            self.g[py][px] = ch

    def region(self, fn, ch, only=None):
        """Paint the letter ch on every pixel whose centre (design coordinates) is inside fn(x, y); only: the letters that may be painted over."""
        for py in range(self.h):
            for px in range(self.n):
                if fn((px + .5) * self.k, (py + .5) * self.k) and (only is None or self.g[py][px] in only):
                    self.g[py][px] = ch

    def fill(self, inside, height, tones, lo=0, hi=6, outline=None, gain=1.0, bias=0.0, family='digit', over=None):
        """inside(x, y) -> bool; height(x, y) -> 0 .. 1 (the dome); tones: the letters from the deepest to the brightest (the 7 of a ramp);
        lo, hi: the tones used; outline: the tone of the edge (a letter) or None; over: only paint where this holds (e.g. not on another shape)."""
        px = {}
        k = self.k
        for y in range(self.h):
            for x in range(self.n):
                if inside((x + .5) * k, (y + .5) * k) and (over is None or over(self, x, y)):
                    px[(x, y)] = None
        for (x, y) in px:
            X, Y = (x + .5) * k, (y + .5) * k
            h = height(X, Y)
            e = .35
            hx = (height(X + e, Y) - height(X - e, Y)) / (2 * e)
            hy = (height(X, Y + e) - height(X, Y - e)) / (2 * e)
            nx, ny, nz = -hx * gain, -hy * gain, 1.0
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            d = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln       # -1 .. 1
            v = max(0.0, min(1.0, .5 + .62 * d + bias))
            px[(x, y)] = tones[lo + int(round(v * (hi - lo)))]
        for (x, y), ch in px.items():
            self.g[y][x] = ch
        if outline is not None:
            for (x, y) in px:
                if any((x + dx, y + dy) not in px for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    self.g[y][x] = outline

    def ellipse(self, cx, cy, rx, ry, tones, **kw):
        def inside(x, y):
            return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0

        def height(x, y):
            q = 1 - ((x - cx) / rx) ** 2 - ((y - cy) / ry) ** 2
            return math.sqrt(max(q, 0.0)) * min(rx, ry) * .9
        self.fill(inside, height, tones, **kw)

    def poly(self, pts, tones, flat=None, ridge=None, **kw):
        """A polygon (a wing). flat: one tone index for the whole inside; else a dome of the distance to the edge (ridge: its height in pixels)."""
        def inside(x, y):
            c = False
            j = len(pts) - 1
            for i in range(len(pts)):
                xi, yi = pts[i]
                xj, yj = pts[j]
                if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                    c = not c
                j = i
            return c

        def edge(x, y):
            best = 1e9
            for i in range(len(pts)):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % len(pts)]
                dx, dy = x2 - x1, y2 - y1
                t = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
                best = min(best, math.hypot(x - (x1 + t * dx), y - (y1 + t * dy)))
            return best
        if flat is not None:
            self.fill(inside, lambda x, y: 1.0, tones, lo=flat, hi=flat, **{k: v for k, v in kw.items() if k not in ('lo', 'hi')})
        else:
            r = ridge or 3.0
            self.fill(inside, lambda x, y: min(edge(x, y), r), tones, **kw)

    def line(self, x0, y0, x1, y1, ch):
        """A line between design points (pixel coordinates 0 .. 31)."""
        a0, b0, a1, b1 = (int(v / self.k) for v in (x0, y0, x1, y1))
        steps = max(abs(a1 - a0), abs(b1 - b0), 1)
        for i in range(steps + 1):
            x, y = round(a0 + (a1 - a0) * i / steps), round(b0 + (b1 - b0) * i / steps)
            if 0 <= x < self.n and 0 <= y < self.h:
                self.g[y][x] = ch

    def rows(self):
        return [''.join(r) for r in self.g]


def write(name, primary, secondary, draw, frames=('a', 'b'), sizes=((32, 32, ''), (24, 24, '.24'))):
    """draw(frame, width, height) -> Canvas. Writes art/master/NAME.txt, NAME.24.txt ...: full rows. sizes: (width, height, file suffix)."""
    paths = []
    for w, h, suffix in sizes:
        out = [f'name: {name}', f'size: {w}x{h}', f'primary: {primary}', f'secondary: {secondary or "-"}', '# made by art/master/%s.py: change that, not this file' % name]
        for f in frames:
            out.append('frame ' + f)
            out += draw(f, w, h).rows()
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'art', 'master', name + suffix + '.txt')
        open(path, 'w').write('\n'.join(out) + '\n')
        paths.append(path)
    return paths
