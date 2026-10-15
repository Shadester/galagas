"""The master art of the creatures, drawn by hand at 32 x 32 (the PSP size); the Amiga versions (24 x 24, AGA 64 colours and OCS 32 colours) are made from it.
A file art/master/NAME.txt:

    name: bee
    primary: blue          the ramp that the digits 0 .. 6 paint (0 = the deepest tone, 6 = the brightest)
    secondary: red         the ramp that the letters h .. n paint (h = deepest, n = brightest); optional
    frame a
    <the rows of the picture, all of the same length>
    frame b
    ...

Other characters: . transparent, y yellow, Y dark yellow, w white, C cyan, D dark cyan, e red (eyes), K black, O orange, P dark orange, s grey, S light grey, b c mid and light blue.
The digits and letters become the letters of the Amiga palette (amiga/tools/art.py: PALETTE, TONE); that is the one place where the colours are."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
sys.path.insert(0, os.path.join(ROOT, 'amiga', 'tools'))
import art  # noqa: E402

MASTER_DIR = os.path.join(ROOT, 'art', 'master')
FIXED = set('.yYwCDeKOPsSbc')


def load(name, suffix=''):
    """-> (primary, secondary, {frame: [rows of palette letters]}) with the digits and letters already turned into palette letters. suffix: '' (the 32 x 32 master), '.24' (the same
    script drawn at 24 pixels), '.16' (the fighter for the Amiga hardware sprite)."""
    primary = secondary = None
    frames, cur = {}, None
    for line in open(os.path.join(MASTER_DIR, name + suffix + '.txt')):
        line = line.split('#')[0].rstrip()
        if not line.strip():
            continue
        if line.startswith('primary:'):
            primary = line.split(':')[1].strip()
        elif line.startswith('secondary:'):
            secondary = line.split(':')[1].strip()
            secondary = None if secondary in ('', '-') else secondary
        elif line.startswith('name:') or line.startswith('size:'):
            pass
        elif line.startswith('frame '):
            cur = line.split()[1]
            frames[cur] = []
        else:
            frames[cur].append(line.strip())
    out = {}
    for f, rows in frames.items():
        assert len(set(len(r) for r in rows)) == 1, (name, f)
        out[f] = [''.join(letter(ch, primary, secondary) for ch in r) for r in rows]
    return primary, secondary, out


def letter(ch, primary, secondary):
    if ch in FIXED:
        return ch
    if ch.isdigit():
        return art.TONE[primary][int(ch)]
    if 'h' <= ch <= 'n' and secondary:
        return art.TONE[secondary][ord(ch) - ord('h')]
    raise ValueError(f'character {ch!r} has no meaning here')


def recolour(rows, table):
    """The same art in another palette: table maps palette letters to palette letters (the purple boss)."""
    return [''.join(table.get(ch, ch) for ch in r) for r in rows]
