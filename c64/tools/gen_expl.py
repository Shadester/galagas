#!/usr/bin/env python3
"""Rewrite the explosion sprites of src/art.asm (expl1 .. expl5: an alien's burst, pexp1 .. pexp6: the fighter's) from art/master/xa.24.txt and xp.24.txt (made by art/master/explode.py).
A sprite is 24 x 21 hires pixels = 12 x 21 multicolour pixels (two hires pixels make one: the first one that is lit wins); the master picture is 24 x 24, the rows 2 .. 22 are used.
Colours: 01 yellow and 11 cyan are shared by all sprites, 10 is the colour of the sprite: it is set for each frame (OWN_ALIEN, OWN_PLAYER; enemies.asm, sprites.asm).
Usage: python3 tools/gen_expl.py"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
MASTER = os.path.join(ROOT, '..', 'art', 'master')
ART = os.path.join(ROOT, 'src', 'art.asm')

# master letter -> multicolour code (a = 01 yellow, b = 10 the colour of the sprite, c = 11 cyan), for each frame
ALIEN = [{'w': 'b', 'e': 'b'},                                                  # the star: light red
         {'y': 'a', 'O': 'b', 'P': 'b', 'e': 'b', 'w': 'c', 'C': 'c'},          # the lump: yellow and orange, cyan dots
         {'w': 'b', 'y': 'a', 'C': 'c', 'O': 'b', 'P': 'b', 'e': 'b'},          # white dots (the colour of the sprite), some yellow and cyan
         {'w': 'b', 'y': 'a', 'e': 'b', 'P': 'b'},
         {'w': 'b', 's': 'b'}]
PLAYER = [{'w': 'b', 'C': 'c', 'D': 'c'}] + [{'w': 'b', 'y': 'a', 'O': 'a', 'P': 'a', 'e': 'b', 'b': 'c', 'c': 'c', 'C': 'c', 'D': 'c', 's': 'b', 'S': 'b'}] * 5
OWN_ALIEN = [10, 8, 1, 1, 15]          # light red, orange, white, white, light grey
OWN_PLAYER = [1, 1, 1, 1, 1, 15]


def frames(name):
    out, cur = [], None
    for line in open(os.path.join(MASTER, name + '.24.txt')).read().split('\n'):
        if line.startswith('frame '):
            cur = []
            out.append(cur)
        elif cur is not None and line:
            cur.append(line)
    return out


def block(title, rows, mapping):
    code = []
    for y in range(2, 23):
        r = rows[y]
        code.append(''.join(next((mapping[c] for c in (r[2 * i], r[2 * i + 1]) if c in mapping), '.') for i in range(12)))
    out = [f'{title}_sprite:', f'    ; {title}', '    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan']
    for line in code:
        bits = ''.join({'.': '00', 'a': '01', 'b': '10', 'c': '11'}[ch] for ch in line)
        out.append('    !byte %{}, %{}, %{}   ; {}'.format(bits[:8], bits[8:16], bits[16:], line))
    out.append('    !byte %00000000                         ; Padding byte to make 64 bytes')
    return '\n'.join(out)


text = open(ART).read()
head = text[:text.index('expl1_sprite:')]
parts = [block(f'expl{i + 1}', rows, ALIEN[i]) for i, rows in enumerate(frames('xa'))]
parts += [block(f'pexp{i + 1}', rows, PLAYER[i]) for i, rows in enumerate(frames('xp'))]
open(ART, 'w').write(head + '\n\n'.join(parts) + '\n')
print('src/art.asm:', len(parts), 'explosion sprites')
