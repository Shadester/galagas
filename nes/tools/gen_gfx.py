#!/usr/bin/env python3
"""Make the graphics of the NES game: gfx/game.chr (the 8 KB of CHR RAM in the game), gfx/title.chr (pattern table 1 on the title screen),
gfx/title.nam (the title screen: name table and attributes), src/gfx.inc (tile and sprite numbers), src/gfx_data.inc (the sprite and palette tables) and src/tables.s (screen mapping).

Pattern table 0 and 1 have the same background tiles, except the formation tiles 64..79: table 0 has wing frame A, table 1 frame B. The game
animates the whole formation with one bit of PPUCTRL (the background table). The sprites are 8 x 16: tiles 128..255 of table 0.
Art: the 16 x 16 creatures of ../psp/art.h (our own art, also the Lynx and Thumby art), the explosions of ../art/master/xa.16.txt and xp.16.txt,
our own 8 x 8 font (tools/font.py), the GALAGA logo of ../docs/logo.png.
Usage: python3 tools/gen_gfx.py [preview.png]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
REPO = os.path.join(ROOT, '..')
sys.path.insert(0, HERE)
from font import GLYPHS  # noqa: E402

# ------------------------------------------------------------------ palettes (NES colour numbers)
BLACK = 0x0F
PAL_GAME = [
    [BLACK, 0x30, 0x16, 0x28],     # BG0: text and HUD: white, red, yellow
    [BLACK, 0x12, 0x16, 0x28],     # BG1: bees and butterflies: blue, red, yellow
    [BLACK, 0x1A, 0x24, 0x28],     # BG2: bosses: green, violet, yellow
    [BLACK, 0x1C, 0x2C, 0x3C],     # BG3: the tractor beam (the game turns the three colours round)
    [BLACK, 0x30, 0x16, 0x12],     # S0: the fighter, its shots and burst: white, red, blue
    [BLACK, 0x12, 0x16, 0x28],     # S1: = BG1
    [BLACK, 0x1A, 0x24, 0x28],     # S2: = BG2
    [BLACK, 0x28, 0x16, 0x30],     # S3: bursts, bombs, stars, the captured fighter: yellow, red, white
]
PAL_TITLE = [
    [BLACK, 0x30, 0x16, 0x28],     # text
    [BLACK, 0x38, 0x27, 0x16],     # the logo: yellow, orange, red
    [BLACK, 0x12, 0x16, 0x28],
    [BLACK, 0x1A, 0x24, 0x28],
    [BLACK, 0x30, 0x16, 0x12],
    [BLACK, 0x12, 0x16, 0x28],
    [BLACK, 0x1A, 0x24, 0x28],
    [BLACK, 0x28, 0x16, 0x30],
]


def tile(rows):
    """8 rows of 8 colour numbers (0..3) -> 16 bytes of an NES tile."""
    lo = bytes(sum(((rows[y][x] & 1) << (7 - x)) for x in range(8)) for y in range(8))
    hi = bytes(sum(((rows[y][x] >> 1) << (7 - x)) for x in range(8)) for y in range(8))
    return lo + hi


def grid(rows, cmap):
    """Rows of letters -> rows of colour numbers (cmap: letter -> number, '.' and anything not in it -> 0)."""
    return [[cmap.get(ch, 0) for ch in r] for r in rows]


def cut(g, x0, y0, w=8, h=8):
    out = []
    for y in range(y0, y0 + h):
        row = []
        for x in range(x0, x0 + w):
            row.append(g[y][x] if 0 <= y < len(g) and 0 <= x < len(g[0]) else 0)
        out.append(row)
    return out


# ------------------------------------------------------------------ the art
src = open(os.path.join(REPO, 'psp', 'art.h')).read()
ART = {}
for m in re.finditer(r'static ArtRows art_(\w+) = \{(.*?)\};', src, re.S):
    rows = re.findall(r'"([^"]*)"', m.group(2))
    ART[m.group(1)] = [r + r[::-1] for r in rows]                       # mirrored: 16 x 16


def master_frames(name):
    frames, cur = [], None
    for line in open(os.path.join(REPO, 'art', 'master', name)).read().split('\n'):
        if line.startswith('frame '):
            cur = []
            frames.append(cur)
        elif cur is not None and line and not line.startswith('#'):
            cur.append(line)
    return frames


# colour numbers of each creature: m main, M light, n dark (outline) and the fixed letters
CMAP = {
    'bee':   {'m': 1, 'M': 1, 'r': 2, 'y': 3, 'Y': 3},                         # BG1 / S1: blue, red, yellow
    'bfly':  {'m': 2, 'M': 2, 'c': 1, 'w': 3, 'y': 3, 'Y': 3},                 # red body, blue and yellow
    'boss':  {'m': 1, 'M': 1, 'c': 2, 'w': 2, 'y': 3, 'Y': 3},                 # BG2 / S2: green body, violet, yellow
    'bossp': {'m': 2, 'M': 2, 'c': 1, 'w': 1, 'y': 3, 'Y': 3},                 # hit once: violet body
    'ship':  {'w': 1, 'c': 3, 'r': 2, 'b': 3},                                 # S0: white, red, blue
    'shipr': {'w': 2, 'c': 3, 'r': 1, 'b': 2},                                 # S3: the captured fighter is red
    'xa':    {'w': 3, 'y': 1, 'Y': 1, 'O': 1, 'P': 2, 'e': 2, 'C': 3, 'D': 3, 'b': 3, 'c': 3, 's': 3, 'S': 3},   # S3
    'xp':    {'w': 1, 'y': 1, 'Y': 1, 'O': 2, 'P': 2, 'e': 2, 'C': 3, 'D': 3, 'b': 3, 'c': 3, 's': 1, 'S': 1},   # S0
}
SHOT = ['.1.', '313', '313', '313', '313', '.3.', '.3.', '.3.']                # S0: white core, blue edge
BOMB = ['.2.', '212', '232', '212', '.2.']                                   # S3: red, yellow, white core

# ------------------------------------------------------------------ pattern table 0: background 0..127, sprites 128..255
bg = {}                       # tile number -> 16 bytes (table 0 and 1)
bg_b = {}                     # tile number -> 16 bytes, table 1 only (wing frame B)
inc = ['; Generated by tools/gen_gfx.py: do not edit.']

bg[0] = tile([[0] * 8] * 8)
for ch, rows in GLYPHS.items():                                              # text: tile = ASCII - 32; letters red, digits and signs white (palette BG0)
    t = ord(ch) - 32
    assert 0 < t < 64, ch
    ink = 2 if ch.isalpha() else 1
    bg[t] = tile([[ink if c == '#' else 0 for c in r] + [0] for r in rows] + [[0] * 8])

FORM = ['bee', 'bfly', 'boss', 'bossp']
T_FORM = 64
for k, name in enumerate(FORM):
    base = 'boss' if name == 'bossp' else name
    for f, store in (('a', bg), ('b', bg_b)):
        g = grid(ART[f'{base}_{f}'], CMAP[name])
        for q, (x0, y0) in enumerate(((0, 0), (8, 0), (0, 8), (8, 8))):
            store[T_FORM + 4 * k + q] = tile(cut(g, x0, y0))
inc.append(f'T_FORM          = {T_FORM}           ; + 4 * kind (bee, butterfly, boss, hit boss) + quarter (top left, top right, bottom left, bottom right)')

# 8 x 8 icons of the HUD (BG0: white, red, yellow): a spare fighter, the stage badges 1, 5, 10
ICONS = {
    'life': ['...1....', '...1....', '..111...', '..121...', '.21112..', '2111112.', '21.1.12.', '........'],
    'b1':   ['.2......', '.2333...', '.23332..', '.2333...', '.2......', '.2......', '.2......', '........'],
    'b5':   ['.2......', '.21113..', '.211133.', '.21113..', '.2......', '.2......', '.2......', '........'],
    'b10':  ['..2.....', '..23333.', '..233333', '..23333.', '..2.....', '..2.....', '.222....', '........'],
}
T_ICON = 80
for k, (name, rows) in enumerate(ICONS.items()):
    bg[T_ICON + k] = tile([[int(c) if c != '.' else 0 for c in r] for r in rows])
    inc.append(f'T_{name.upper():<14}= {T_ICON + k}')
T_BEAM = 88                                                                  # 88..127: the tractor beam, drawn by the game in CHR RAM
inc.append(f'T_BEAM          = {T_BEAM}           ; 88..127: the tractor beam (made by the game)')

spr = {}                                                                     # tile number (128..255) -> bytes
SPR = []                                                                     # (name, first tile, symmetric)
nxt = [128]


def add_sprite(name, g, symmetric):
    """A 16 x 16 picture -> 8 x 16 tile pairs: the left half (and the right half when it is not symmetric: the right half is the left one turned)."""
    t = nxt[0]
    halves = [0] if symmetric else [0, 8]
    for x0 in halves:
        spr[nxt[0]] = tile(cut(g, x0, 0))
        spr[nxt[0] + 1] = tile(cut(g, x0, 8))
        nxt[0] += 2
    SPR.append((name, t, symmetric))


for name in FORM:
    base = 'boss' if name == 'bossp' else name
    for f in 'ab':
        add_sprite(f'{name}_{f}', grid(ART[f'{base}_{f}'], CMAP[name]), True)
add_sprite('ship', grid(ART['player'], CMAP['ship']), True)
add_sprite('shipr', grid(ART['player'], CMAP['shipr']), True)
for n, rows in enumerate(master_frames('xa.16.txt'), 1):
    add_sprite(f'expl{n}', grid(rows, CMAP['xa']), False)
for n, rows in enumerate(master_frames('xp.16.txt'), 1):
    add_sprite(f'pexp{n}', grid(rows, CMAP['xp']), False)
# the shot and the bomb: one 8 x 16 sprite each, drawn at the left edge of its tile
shot = [[int(c) if c != '.' else 0 for c in r] for r in SHOT]
bomb = [[int(c) if c != '.' else 0 for c in r] for r in BOMB]
add_sprite('shot', shot, True)
add_sprite('bomb', bomb, True)
for k in (1, 2, 3):                                                          # a star: one pixel of colour 1, 2 or 3 (palette S3: yellow, red, white)
    add_sprite(f'star{k}', [[k]], True)
assert nxt[0] <= 256, nxt[0]

# Sprite ids (the order of the Lynx ids, lynx/src/portrait/art.inc): spr_tile = the first tile, spr_flags = palette | $40 one 8 pixel column |
# $80 two different halves (the right half is the next tile pair; else the left half turned)
IDS = [('player', 'ship', 0), ('player_red', 'shipr', 3), ('pbul', 'shot', 0), ('ebul', 'bomb', 3),
       ('bee_a', 'bee_a', 1), ('bee_b', 'bee_b', 1), ('bfly_a', 'bfly_a', 1), ('bfly_b', 'bfly_b', 1),
       ('boss_a', 'boss_a', 2), ('boss_b', 'boss_b', 2), ('bossp_a', 'bossp_a', 2), ('bossp_b', 'bossp_b', 2)]
IDS += [(f'expl{n}', f'expl{n}', 3) for n in range(1, 6)] + [(f'pexp{n}', f'pexp{n}', 0) for n in range(1, 7)]
IDS += [(f'star{k}', f'star{k}', 3) for k in (1, 2, 3)]
first = {name: (t, sym) for name, t, sym in SPR}
inc.append('; the first tile of every picture')
for name, t, sym in SPR:
    inc.append(f'S_{name.upper():<12}= {t}')
inc.append('; sprite ids')
tiles, flags = [], []
for i, (sid, name, pal) in enumerate(IDS):
    t, sym = first[name]
    narrow = name in ('shot', 'bomb') or name.startswith('star')
    tiles.append(t)
    flags.append(pal | (0x40 if narrow else 0) | (0 if sym else 0x80))
    inc.append(f'SP_{sid.upper():<12}= {i}')
dat = ['; Generated by tools/gen_gfx.py: do not edit. The tables of the sprite ids and the palettes (included in RODATA).']
dat.append('spr_tile:       .byte ' + ', '.join(map(str, tiles)))
dat.append('spr_flags:      .byte ' + ', '.join('$%02X' % f for f in flags))

# ------------------------------------------------------------------ the CHR RAM of the game: table 0 and table 1
def table(bgtiles, sprtiles):
    out = bytearray(4096)
    for t, b in bgtiles.items():
        if b is not None:
            out[t * 16:t * 16 + 16] = b
    for t, b in sprtiles.items():
        out[t * 16:t * 16 + 16] = b
    return out


t0 = table(bg, spr)
t1 = table({**bg, **{k: v for k, v in bg_b.items() if v is not None}}, {})
os.makedirs(os.path.join(ROOT, 'gfx'), exist_ok=True)
open(os.path.join(ROOT, 'gfx', 'game.chr'), 'wb').write(bytes(t0 + t1))

# ------------------------------------------------------------------ the title: the logo in pattern table 1 (tiles 64..255) and the name table
from PIL import Image  # noqa: E402
logo = Image.open(os.path.join(REPO, 'docs', 'logo.png')).convert('RGB')
box = (95, 25, 593, 115)                                                     # the letters (tools: the bounding box of the bright pixels)
LW, LH = 208, 38
src_px = logo.load()
LOGO_RGB = {1: (254, 231, 55), 2: (253, 148, 34), 3: (190, 30, 30)}


def nearest(c):
    if sum(c) < 120:
        return 0
    return min(LOGO_RGB, key=lambda k: sum((a - b) ** 2 for a, b in zip(c, LOGO_RGB[k])))


lg = []
for y in range(LH):
    row = []
    for x in range(LW):
        votes = {}
        x0 = box[0] + (box[2] - box[0]) * x / LW
        y0 = box[1] + (box[3] - box[1]) * y / LH
        x1 = box[0] + (box[2] - box[0]) * (x + 1) / LW
        y1 = box[1] + (box[3] - box[1]) * (y + 1) / LH
        for sy in range(int(y0), max(int(y0) + 1, int(y1))):
            for sx in range(int(x0), max(int(x0) + 1, int(x1))):
                k = nearest(src_px[sx, sy])
                votes[k] = votes.get(k, 0) + 1
        row.append(max(votes, key=lambda k: (votes[k], k)))
    lg.append(row)
LH8 = (LH + 7) // 8
title_tiles = {}                                                             # bytes -> tile number
title_bg = dict(bg)
nam = [[0] * 32 for _ in range(30)]
LX, LY = (32 - LW // 8) // 2, 4                                              # the logo: tile column 3, row 4
nt = 64
for ty in range(LH8):
    for tx in range(LW // 8):
        b = tile(cut(lg, tx * 8, ty * 8))
        if b == bg[0]:
            nam[LY + ty][LX + tx] = 0
            continue
        if b not in title_tiles:
            title_tiles[b] = nt
            title_bg[nt] = b
            nt += 1
        nam[LY + ty][LX + tx] = title_tiles[b]
assert nt <= 256, nt
attr = [[0] * 8 for _ in range(8)]                                           # the logo's area has palette 1
for ty in range(LY, LY + LH8):
    for tx in range(LX, LX + LW // 8):
        attr[ty // 4][tx // 4] |= 1 << (((ty // 2) & 1) * 4 + ((tx // 2) & 1) * 2)
nt_bytes = bytes(sum(nam, [])) + bytes(sum(attr, []))
open(os.path.join(ROOT, 'gfx', 'title.chr'), 'wb').write(bytes(table(title_bg, {})))
open(os.path.join(ROOT, 'gfx', 'title.nam'), 'wb').write(nt_bytes)
inc.append(f'; the title logo: {nt - 64} tiles')

# The attributes of the game (16 x 16 pixel areas): the HUD and the messages palette 0 (text), the boss row (tile rows 2, 3, columns 8..23)
# palette 2, the other rows of the formation (tile rows 4..17) palette 1, the rows of the messages and the ship (18..29) palette 0
def attr_q(r, c):
    return 2 if 2 <= r <= 3 and 8 <= c <= 23 else 1 if 4 <= r <= 17 else 0


ag = [attr_q(ar, ac) | attr_q(ar, ac + 2) << 2 | attr_q(ar + 2, ac) << 4 | attr_q(ar + 2, ac + 2) << 6 for ar in range(0, 32, 4) for ac in range(0, 32, 4)]
dat.append('attr_game:      .byte ' + ', '.join('$%02X' % v for v in ag))
dat.append('pal_game_data:  .byte ' + ', '.join('$%02X' % c for p in PAL_GAME for c in p))
dat.append('pal_title_data: .byte ' + ', '.join('$%02X' % c for p in PAL_TITLE for c in p))
open(os.path.join(ROOT, 'src', 'gfx.inc'), 'w').write('\n'.join(inc) + '\n')
open(os.path.join(ROOT, 'src', 'gfx_data.inc'), 'w').write('\n'.join(dat) + '\n')

# ------------------------------------------------------------------ the screen mapping: game units -> NES pixels
# x: 8 / 7 (the formation columns, 14 units apart, are 16 pixels apart: two tiles), u = x + 35 (x -35..220), pixel = u * 8 / 7 - 28 (16 bit, signed).
# y: the centre of a 16 unit box (c = y + 8) -> the line Y(c): one line a unit down to c = 124 (the formation, so its rows are 16 lines apart and
# on the 16 line grid of the attributes), then fewer (the slope falls to s_min at c = 174 and stays there), so that the ship (c = 250) is at line
# 223. The top of the box = Y(c) - 8.
XU = 35
xmap = [u * 8 // 7 - 28 for u in range(256)]
KNEE, KNEE2, SHIP_C, SHIP_LINE = 124, 174, 250, 223
s_min = (SHIP_LINE - KNEE - (KNEE2 - KNEE) / 2) / ((KNEE2 - KNEE) / 2 + SHIP_C - KNEE2)


def Y(c):
    if c <= KNEE:
        return c
    if c <= KNEE2:
        d = c - KNEE
        return KNEE + d - (1 - s_min) * d * d / (2 * (KNEE2 - KNEE))
    return Y(KNEE2) + s_min * (c - KNEE2)


ymap = []
for y in range(256):
    top = round(Y(y + 8)) - 8
    ymap.append(top if 0 <= top <= 232 and y < 255 else 255)
assert abs(Y(SHIP_C) - SHIP_LINE) < 0.01
tab = ['; Generated by tools/gen_gfx.py: do not edit. The screen mapping (see the generator).',
       f'; x: pixel = xmap[x + {XU}] (16 bit, signed); y: the top line of a 16 unit box at y (255: not on the screen); slope below the formation {s_min:.3f}',
       '        .export xmap_lo, xmap_hi, ymap', '', '        .segment "RODATA"']
for name, vals in (('xmap_lo', [v & 255 for v in xmap]), ('xmap_hi', [(v >> 8) & 255 for v in xmap]), ('ymap', ymap)):
    tab.append(f'{name}:')
    for i in range(0, 256, 16):
        tab.append('        .byte ' + ', '.join('$%02X' % v for v in vals[i:i + 16]))
open(os.path.join(ROOT, 'src', 'tables.s'), 'w').write('\n'.join(tab) + '\n')
print('gfx/game.chr, gfx/title.chr, gfx/title.nam, src/gfx.inc, src/gfx_data.inc, src/tables.s:', len(SPR), 'sprites up to tile', nxt[0] - 1, '- logo tiles', nt - 64,
      '- slope %.3f' % s_min)

# ------------------------------------------------------------------ preview
if len(sys.argv) > 1:
    NES_RGB = {0x0F: (0, 0, 0), 0x30: (255, 254, 255), 0x16: (181, 49, 32), 0x28: (234, 158, 34), 0x12: (75, 50, 200), 0x1A: (56, 135, 0),
               0x24: (228, 92, 228), 0x1C: (21, 95, 218), 0x2C: (56, 204, 220), 0x3C: (121, 255, 255), 0x27: (237, 106, 50)}
    S = 4
    out = Image.new('RGB', (256 * S, 200 * S))

    def put(g, pal, ox, oy):
        for y, r in enumerate(g):
            for x, v in enumerate(r):
                if v:
                    for dy in range(S):
                        for dx in range(S):
                            out.putpixel((ox + x * S + dx, oy + y * S + dy), NES_RGB[pal[v]])
    ox = 4
    for name in FORM:
        base = 'boss' if name == 'bossp' else name
        pal = PAL_GAME[2 if base == 'boss' else 1]
        for f in 'ab':
            put(grid(ART[f'{base}_{f}'], CMAP[name]), pal, ox, 4)
            ox += 18 * S
    put(grid(ART['player'], CMAP['ship']), PAL_GAME[4], ox, 4)
    put(grid(ART['player'], CMAP['shipr']), PAL_GAME[7], ox + 18 * S, 4)
    ox = 4
    for rows in master_frames('xa.16.txt'):
        put(grid(rows, CMAP['xa']), PAL_GAME[7], ox, 24 * S)
        ox += 18 * S
    ox = 4
    for rows in master_frames('xp.16.txt'):
        put(grid(rows, CMAP['xp']), PAL_GAME[4], ox, 44 * S)
        ox += 18 * S
    put(shot, PAL_GAME[4], 4, 64 * S)
    put(bomb, PAL_GAME[7], 12 * S, 64 * S)
    ox = 4
    for k, ch in enumerate('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-%!.:\',/?'):
        put([[1 if c == '#' else 0 for c in r] for r in GLYPHS[ch]], PAL_GAME[0], 4 + (k % 32) * 8 * S, (80 + 8 * (k // 32)) * S)
    for k, rows in enumerate(ICONS.values()):
        put([[int(c) if c != '.' else 0 for c in r] for r in rows], PAL_GAME[0], 4 + k * 10 * S, 100 * S)
    put(lg, PAL_TITLE[1], 4, 112 * S)
    out.save(sys.argv[1])
