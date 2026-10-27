#!/usr/bin/env python3
"""Screenshot regression tests: build each case with its debug flags, run it headless in cynes and compare the picture with
tests/ref/<case>.png.

Every case builds with -DHALT=n: the game freezes after n ticks (it keeps drawing: the picture is complete), so the screenshot is exact
(cynes is deterministic: the compare allows only a few different pixels). Usage:
    tests/run.py [--update] [case ...]
"""
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import cynes
from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
LIMIT = 8           # different pixels allowed
SETTLE = 20         # frames after the freeze: the last rows of the name table are copied

# name | flags | game ticks until the game freezes (-DHALT)
CASES = '''
title||100
entry|AUTOPLAY=1 NOFIRE=1|300
formation|AUTOPLAY=1 NOFIRE=1|1300
play|AUTOPLAY=1|1500
dive|AUTOPLAY=1 NOFIRE=1|2600
challenge|AUTOPLAY=1 STAGE=3 NOFIRE=1|600
chalresult|AUTOPLAY=1 STAGE=3|1500
explode|AUTOPLAY=1 NOFIRE=1 DIEAT=1100|1125
ready|AUTOPLAY=1 NOFIRE=1 LIVES=9 DIEAT=250|400
pause|AUTOPLAY=1 NOFIRE=1 PAUSEAT=1100|1140
beam|AUTOPLAY=1 CAPTURE=1 GODBEAM=1 LIVES=9|1640
capture|AUTOPLAY=1 CAPTURE=1 GODBEAM=1 LIVES=9|3144
captured|AUTOPLAY=1 CAPTURE=1 GODBEAM=1 LIVES=9|3240
dual|AUTOPLAY=1 DUAL=1 GODMODE=1|1500
quit|AUTOPLAY=1 QUITAT=1100|1200
gameover|AUTOPLAY=1 NOFIRE=1 LIVES=1 HALTOVER=1|2200
'''


def run_case(case):
    name, flags, ticks = case
    out = os.path.join(ROOT, 'build', 'test', name)
    shutil.rmtree(out, ignore_errors=True)               # the Makefile does not see changed flags
    defs = ' '.join(f'-D {f}' for f in flags.split()) + f' -D HALT={ticks}'
    subprocess.run(['make', '-C', ROOT, 'BUILD=' + os.path.relpath(out, ROOT), f'CAFLAGS={defs}'], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    lb = {m.group(2): int(m.group(1), 16) for m in re.finditer(r'al ([0-9A-F]+) \.(\w+)', open(os.path.join(out, 'galaga.lbl')).read())}
    nes = cynes.NES(os.path.join(out, 'galaga.nes'))
    nes.step(30)
    for _ in range(ticks * 2):                           # until it freezes (a slow tick: the NES may need more frames than ticks * 6 / 5)
        if nes[lb['halted']] == 1:
            break
        nes.step(1)
    fb = nes.step(SETTLE)
    png = out + '.png'
    Image.fromarray(fb).save(png)
    return name, png


def same(a, b):
    ia, ib = Image.open(a).convert('RGB'), Image.open(b).convert('RGB')
    if ia.size != ib.size:
        return False
    diff = ImageChops.difference(ia, ib).convert('L').point(lambda v: 255 if v else 0)
    return diff.histogram()[255] <= LIMIT


def main():
    args = sys.argv[1:]
    update = args[:1] == ['--update']
    names = args[1:] if update else args
    cases = [tuple(c.split('|')) for c in CASES.strip().splitlines()]
    cases = [(n, f, int(h)) for n, f, h in cases if not names or n in names]
    os.makedirs(os.path.join(ROOT, 'build', 'test'), exist_ok=True)
    refdir = os.path.join(HERE, 'ref')
    os.makedirs(refdir, exist_ok=True)
    fail = 0
    with ThreadPoolExecutor(4) as pool:
        for name, png in pool.map(run_case, cases):
            ref = os.path.join(refdir, name + '.png')
            if update:
                os.replace(png, ref)
                print('UPDATED', name)
            elif os.path.exists(ref) and same(png, ref):
                print('PASS', name)
            else:
                print('FAIL', name, '(see', png + ')')
                fail = 1
    return fail


sys.exit(main())
