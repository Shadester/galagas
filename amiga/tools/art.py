"""The palette and the pictures of the Amiga game: 32 colours (5 bitplanes, OCS), 64 colours on an AGA machine (6 bitplanes).

The creatures are drawn by hand: art/master/*.py (shapes with lit tones and outlines, tools/sprites/paint.py), at 32 x 32 for the PSP and at 24 x 24 for the Amiga (the fighter 16 x 20: a
hardware sprite, two attached sprites with 15 colours, so its colours are in entries 17 .. 31 of the palette, and so are the colours of the stars (25, 26, 27, hardware sprites 4 and 5)
and of the shots (29, 30, hardware sprites 6 and 7)). The AGA game uses the 7 tones of each ramp, the OCS game 4 (tools/sprites/reduce.py to_ocs).
Every letter of the art is one palette entry (PALETTE, and the tones below); '.' is transparent."""

# letter, rgb. The index of a letter is its place in this list (0 is the background, black).
PALETTE = [
    ('K', (0, 0, 0)),                                                           # 0 black (also an opaque black in a sprite)
    ('w', (255, 255, 255)),                                                     # 1 white (text)
    ('R', (238, 34, 0)),                                                        # 2 red (text)
    ('g', (0, 110, 44)), ('h', (0, 204, 68)), ('i', (150, 255, 160)),           # 3-5 green (the boss): dark, mid, light
    ('j', (110, 30, 140)), ('k', (204, 68, 221)), ('l', (236, 176, 248)),       # 6-8 purple (the boss, hit)
    ('Y', (200, 150, 0)),                                                       # 9 dark yellow
    ('O', (255, 136, 0)), ('P', (176, 68, 0)),                                  # 10-11 orange, dark orange (explosions)
    ('B', (40, 90, 210)),                                                       # 12 blue of the beam
    ('A', (20, 31, 105)), ('E', (83, 9, 0)), ('I', (0, 61, 24)), ('V', (61, 17, 77)),   # 13-16 the deepest tone of blue, red, green, purple (the outline of an alien)
    ('W', (255, 255, 255)),                                                     # 17 white (the ship)
    ('a', (36, 56, 190)), ('b', (68, 102, 255)), ('c', (150, 182, 255)),        # 18-20 blue: dark, mid, light (the bee, the ship)
    ('e', (238, 40, 8)), ('d', (150, 16, 0)), ('f', (255, 140, 110)),           # 21-23 red: mid, dark, light (the butterfly, the ship)
    ('y', (255, 255, 0)),                                                       # 24 yellow
    ('s', (132, 132, 164)), ('5', (60, 60, 96)), ('S', (210, 210, 240)),        # 25-27 grey; the stars of hardware sprites 4 and 5 are mid, dim, bright
    ('C', (0, 204, 221)),                                                       # 28 cyan
    ('D', (0, 120, 140)), ('L', (170, 225, 255)),                               # 29-30 the shot (hardware sprites 6 and 7), the beam
    ('t', (40, 40, 70)),                                                        # 31 text shadow
]
PEN = {'.': 0}
for i, (ch, _) in enumerate(PALETTE):
    PEN[ch] = i
COLOURS = [rgb for _, rgb in PALETTE]
assert len(PALETTE) == 32
TEXT_WHITE, TEXT_RED, TEXT_CYAN, TEXT_SHADOW = PEN['w'], PEN['R'], PEN['C'], PEN['t']


# ---- the shot of the fighter: hardware sprite 6 / 7, 4 pixels wide: pixel values 13, 14, 15 = entries 29 (D), 30 (L), 31 (t) ----
PBUL = ['.LL.', '.LL.', 'DLLD', 'DLLD', 'DLLD', 'DLLD', 'DLLD', 'DLLD', 'DLLD', 'tDDt', 'tDDt', '.DD.', '.tt.', '.tt.']
# ---- the bomb of an alien: a red drop with a yellow core and a flame above it (it falls), two frames; blitted in the playfield colours ----
EBUL = ['..dd..', '..ee..', '.eeee.', '.eyye.', 'eyyyye', 'eyywye', 'eyyyye', '.eyye.', '.eeee.', '..ee..', '..dd..']
EBUL2 = ['..d...', '..ee..', '.eeee.', 'eeyyee', 'eyyyye', 'eywwye', '.eyyye', '.eyye.', '..eee.', '..ee..', '...d..']


# ---- AGA: 64 colours. The first 32 are the same (the text and the hardware sprites use them); the others make the aliens smoother: every body colour has 7 tones instead of 3 ----
RAMPS = {'blue': 'abc', 'red': 'def', 'green': 'ghi', 'purple': 'jkl'}                 # dark, mid, light (the letters of PALETTE)
assert not set('QJTFGHMNUXZ0') & set(ch for ch, _ in PALETTE)           # (a clash would change the pen of a letter of the OCS art)
DEEP = {'blue': 'A', 'red': 'E', 'green': 'I', 'purple': 'V'}                   # tone 0 of a ramp: in the OCS palette too (entries 13 .. 16)
EXTRA_LETTERS = {'blue': 'QJT', 'red': 'FGH', 'green': 'MNU', 'purple': 'XZ0'}  # the AGA tones 2, 4, 6 of a ramp (7 tones: 0 deepest .. 6 brightest; the old ones are 1, 3, 5)


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _tones(ramp):
    d, m, l = (COLOURS[PEN[ch]] for ch in RAMPS[ramp])
    return [COLOURS[PEN[DEEP[ramp]]], d, _lerp(d, m, .5), m, _lerp(m, l, .5), l, _lerp(l, (255, 255, 255), .55)]


COLOURS64 = list(COLOURS)
TONE = {}                                                                             # ramp -> the 7 letters
for _r, _letters in RAMPS.items():
    tones = _tones(_r)
    TONE[_r] = [DEEP[_r], _letters[0], EXTRA_LETTERS[_r][0], _letters[1], EXTRA_LETTERS[_r][1], _letters[2], EXTRA_LETTERS[_r][2]]
    for _i in (2, 4, 6):
        PEN[TONE[_r][_i]] = len(COLOURS64)
        COLOURS64.append(tones[_i])
COLOURS64 += [(0, 0, 0)] * (64 - len(COLOURS64))


# ---- the creatures, from art/master (made by art/master/*.py) ----
import os
import sys

_SPRITES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools', 'sprites')


def _tools():
    if _SPRITES not in sys.path:
        sys.path.insert(0, _SPRITES)
    import master
    import reduce
    return master, reduce


def hand(name, aga=False):
    """An alien: bee_a, bee_b, bfly_a, bfly_b, boss_a, boss_b, bossp_a, bossp_b (the hit boss: purple), 24 x 24. aga: 7 tones for each ramp; else 4."""
    master, reduce = _tools()
    kind, f = name.split('_')
    rows = master.load('boss' if kind == 'bossp' else kind, '.24')[2][f]
    if kind == 'bossp':
        rows = master.recolour(rows, {TONE['green'][i]: TONE['purple'][i] for i in range(7)})
    return rows if aga else reduce.to_ocs(rows)


def ship():
    """The fighter, 16 x 20: a hardware sprite (the colours of the entries 17 .. 31)."""
    master, _ = _tools()
    return master.recolour(master.load('ship', '.16')[2]['a'], {'w': 'W'})


def captive():
    """The same ship, red (the fighter that the boss has captured): blitted, in the playfield colours."""
    master, _ = _tools()
    return master.recolour(ship(), {'W': 'f', 'S': 'f', 's': 'e', 'a': 'd', 'b': 'e', 'c': 'f', 'C': 'W', 'D': 's', 'e': 'y', 'd': 'Y', 'f': 'y'})


def small_ship():
    """The lives in the hud: the ship at half the size, 8 x 10."""
    _, reduce = _tools()
    return reduce.reduce_rows(ship(), 8, 10)


def explosion(name):
    """xa0 .. xa2: an alien, xp0 .. xp3: the fighter; 24 x 24, in fixed colours."""
    master, _ = _tools()
    return master.load(name[:2], '.24')[2]['abcd'[int(name[2])]]
