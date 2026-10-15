"""Pixel art of the Amiga game, at 1-pixel resolution, in a 32-colour palette (5 bitplanes).

The aliens are the designs of ../psp/art.h drawn again at the size of the Amiga screen: 24 pixels wide (the left half, 12 pixels, is given; it is
mirrored). The ship is 16 pixels wide: it is a hardware sprite (two attached sprites, 15 colours), so its colours are in entries 17 .. 31 of
the palette, and so are the colours of the stars (25, 26, 27, hardware sprites 4 and 5) and of the shots (29, 30, hardware sprites 6 and 7).
Every letter of the art is one palette entry (PALETTE); '.' is transparent."""

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
    ('1', (0, 0, 0)), ('2', (0, 0, 0)), ('3', (0, 0, 0)), ('4', (0, 0, 0)),     # 13-16 spare
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


def mirror(half):
    return [r + r[::-1] for r in half]


def recolour(rows, table):
    return [''.join(table.get(ch, ch) for ch in r) for r in rows]


# ---- the aliens: left halves, two wing frames ----
BEE_A = [
    "....yy......", ".....yy.....", "......yy....", "aaa....bbbbb", "aaaa..bbbbbb", "aacaa.bbcccb", "aacccabbeeeb", "aacccabbeebb",
    "aacccabbbKKb", ".aaccbbbbbbb", "..acbbbbbbbb", "...aabbbYyyy", "....aabbbbbb", ".....abbbbbb", "......bbYyyy", "......aabbbb",
    "......aabbbb", ".......aabbb", ".........aaa", ".........aaa", "..........aa"]
BEE_B = [
    "....yy......", ".....yy.....", "......yy....", ".......bbbbb", "......bbbbbb", "......bbcccb", "....aabbeeeb", "....aabbeebb",
    "....aabbbKKb", ".aa.aabbbbbb", "aaaaaabbbbbb", "aacaa.bbYyyy", "aacccabbbbbb", "aacccabbbbbb", "aacccabbYyyy", ".aaccbaabbbb",
    "..acbbaabbbb", "...aab.aabbb", ".........aaa", ".........aaa", "..........aa"]
BFLY_A = [
    "...yy....yy.", "...yyy..yy..", "....yy.yy...", "ffe....CCCCC", "ffee.d.CCCCC", "fffeed.CCwwC", "ffyffeddCwwC", "ffyffeddCwCC",
    "eefyyfddCCCC", ".eeeeeeeeeee", "..eeeeeeeeee", ".ddeeeeeyyye", "...ddeeeeeee", "...ddeeeeeee", "...dddeeeeef", "....ddeeeffe",
    ".....deeefee", "......ddeeee", ".......dddde", ".......dddde"]
BFLY_B = [
    "....yy...yy.", ".....y..yy..", ".......yy...", "....ffeeCCCC", "....ffeCCCCC", "....ffffCwwC", "...ffyffCwwC", "...ffyfCCwCC",
    "...eefyyCCCC", "....eeeeeeee", ".....eeeeeee", "....ddeeyyye", "......eeeeee", ".....deeeeee", "....ddeeeeef", "....eeeeeffe",
    "....eeeeefee", "....eeddeeee", ".......dddde", ".......dddde"]
BOSS_A = [
    ".........CCC", ".....C..CCCC", "....CC.CCCCw", "...CCCyyyCCC", "...CCCyyyCCC", "...yyyyyyyyC", "...gghhhhhhi", "..ggihhhhhhi",
    ".ggiiihhhhhh", ".hhiiYyyhhhY", "ghhiYYyyhhhY", "gghhhYyyYhhh", "ggghhhhhhhhh", "ggghhhhhhhhh", "gggggihhhhhh", "...ggghhhhhh",
    "..gggghhhhhh", ".gghhg.hhhhh", "ggh.gg.gghhh", "ggh.gg..ghhh", "gg..gg...ggg"]
BOSS_B = [
    ".........CCC", ".....C..CCCC", "....CC.CCCCw", "...CCCyyyCCC", "...CCCyyyCCC", "...yyyyyyyyC", "...gghhhhhhi", "..ggihhhhhhi",
    ".ggiiihhhhhh", ".hhiiYyyhhhY", "ghhiYYyyhhhY", "gghhhYyyYhhh", "ggghhhhhhhhh", "ggghhhhhhhhh", "gggggihhhhhh", "...ggghhhhhh",
    "...ggghhhhhh", "...ggghhhhhh", "....gghhghhh", "....gghgghhh", "....gggg.ggg"]
PURPLE = {'g': 'j', 'h': 'k', 'i': 'l'}


def hand(name):
    kind, f = name.split('_')
    half = {'bee': (BEE_A, BEE_B), 'bfly': (BFLY_A, BFLY_B), 'boss': (BOSS_A, BOSS_B), 'bossp': (BOSS_A, BOSS_B)}[kind][f == 'b']
    rows = mirror(half)
    return recolour(rows, PURPLE) if kind == 'bossp' else rows


# ---- the ship: 16 pixels wide, a hardware sprite (the colours are in entries 17 .. 31) ----
SHIP_HALF = [
    ".......W", ".......W", "......WW", "......WW", "......WC", ".....WWC", ".....WWC", ".....cWW", "....bcWW", "....bbWW",
    "e...bbWW", "e..abbbW", "ee.abbbb", "eeaabcbb", "ebbbbcbb", "WbbbbbWb", "WbbbbbWb", "Wabb.bbb", "Wa....sa", ".ee..yyd"]


def ship():
    return mirror(SHIP_HALF)


def captive():
    """The same ship, red (the fighter that the boss has captured): blitted, as the playfield colours (the red of 21, 22, 23)."""
    return recolour(ship(), {'W': 'f', 'a': 'd', 'b': 'e', 'c': 'f', 'e': 'y', 'C': 'W', 'y': 'e', 's': 'd'})


def small_ship():
    """The lives in the hud: every second pixel of the ship."""
    rows = ship()
    return [''.join(r[x] for x in range(0, 16, 2)) for r in rows[::2]]


# ---- the shot of the fighter: hardware sprite 6 / 7, pixel values 13, 14, 15 = entries 29, 30, 31 ----
PBUL = ['LD', 'LD', 'LD', 'LD', 'LD', 'LD', 'LD', 'DD', 'D.', 'D.']
EBUL = ['.yy.', 'yyyy', 'yeey', 'yeey', 'deed', 'deed', 'deed', 'deed', '.dd.']


# ---- explosions: the art of ../psp/art.h (3 frames for an alien, 4 for the fighter), 1.5 times as big (every third pixel doubled, a majority vote) ----
import os
import re
from collections import Counter

_H = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'psp', 'art.h')).read()
PSP = {m.group(1): re.findall(r'"([^"]*)"', m.group(2)) for m in re.finditer(r'static ArtRows art_(\w+) = \{(.*?)\};', _H, re.S)}
_X = {'o': 'O', 'y': 'y', 'w': 'w', 'c': 'C', 'r': 'e'}


def explosion(name):
    full = [''.join(_X.get(ch, ch) for ch in (r + r[::-1])) for r in PSP[name]]
    h, w = len(full), len(full[0])
    big = [[full[y // 3][x // 3] for x in range(w * 3)] for y in range(h * 3)]
    out = []
    for y in range(0, h * 3, 2):
        row = ''
        for x in range(0, w * 3, 2):
            cells = [big[yy][xx] for yy in range(y, min(y + 2, h * 3)) for xx in range(x, min(x + 2, w * 3))]
            row += max(Counter(cells).most_common(), key=lambda t: (t[1], t[0] != '.'))[0]
        out.append(row)
    return out
