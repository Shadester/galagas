#!/usr/bin/env python3
"""Same picture, new code: builds a reference commit (a git worktree) and this tree with the same flags, freezes both at many ticks
(-DAUTOPLAY -DHALT=n), and compares the two screens pixel by pixel. For a change that must not change what is drawn (speed work).
Usage: python3 tests/compare.py [--ref COMMIT] [--flags "-DNOASM"] [--quick] [case ...]
The pictures of the reference are kept in build/cmp/ref-<commit>-<case>.png: a second run builds only this tree."""
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
REPO = os.path.join(ROOT, '..')
sys.path.insert(0, HERE)
from vamiga import Session  # noqa: E402

AUTO = '-DAUTOPLAY -DTITLE_HOLD=0'
CASES = {}
for t in (60, 130, 250, 400, 520, 700, 950, 1300, 1800, 2400, 3100):
    CASES[f'play{t}'] = (AUTO, t)
for t in (150, 400, 800):
    CASES[f'chal{t}'] = (AUTO + ' -DSTART_STAGE=3', t)
for t in (300, 900, 1700):
    CASES[f'late{t}'] = (AUTO + ' -DSTART_STAGE=11', t)
for t in (5450, 5500, 5560, 5650):                              # the tractor beam (the first one of the autoplay game is at tick 5389 and lasts about 300 ticks)
    CASES[f'beam{t}'] = (AUTO, t)
QUICK = ['play130', 'play400', 'play950', 'chal400', 'late900']

args = sys.argv[1:]
ref = 'HEAD'
flags = ''
quick = '--quick' in args
if '--ref' in args:
    ref = args[args.index('--ref') + 1]
if '--flags' in args:
    flags = args[args.index('--flags') + 1]
names = [a for a in args if a in CASES] or (QUICK if quick else list(CASES))
sha = subprocess.run(['git', '-C', REPO, 'rev-parse', '--short', ref], check=True, capture_output=True, text=True).stdout.strip()
cmp_dir = os.path.join(ROOT, 'build', 'cmp')
os.makedirs(cmp_dir, exist_ok=True)
wt = os.path.join(cmp_dir, 'wt-' + sha)
if not os.path.isdir(wt):
    subprocess.run(['git', '-C', REPO, 'worktree', 'add', '--detach', wt, sha], check=True, capture_output=True)


def shot(tree, build, case, extra_flags, out):
    cflags, halt = CASES[case]
    shutil.rmtree(os.path.join(tree, build), ignore_errors=True)
    subprocess.run(['make', '-C', tree, f'BUILD={build}', f'EXTRA_CFLAGS={cflags} -DHALT={halt} {extra_flags}'], check=True, capture_output=True)
    with Session(os.path.join(tree, build, 'galaga.adf'), warp=100000) as s:
        s.settle(out)


def run(case):
    ref_png = os.path.join(cmp_dir, f'ref-{sha}-{case}.png')
    new_png = os.path.join(cmp_dir, f'new-{case}.png')
    if not os.path.exists(ref_png):
        shot(os.path.join(wt, 'amiga'), 'build/cmp_ref_' + case, case, '', ref_png)
    shot(ROOT, 'build/cmp_new_' + case, case, flags, new_png)
    a, b = Image.open(ref_png).convert('RGB'), Image.open(new_png).convert('RGB')
    d = ImageChops.difference(a, b).convert('L').point(lambda v: 255 if v else 0)
    n = sum(1 for v in (d.get_flattened_data() if hasattr(d, 'get_flattened_data') else d.getdata()) if v)
    return case, n


with ThreadPoolExecutor(4) as ex:
    results = list(ex.map(run, names))
bad = 0
for case, n in results:
    print(f'{case}: {"same" if n == 0 else f"DIFFERENT ({n} pixels, see build/cmp/new-{case}.png and ref-{sha}-{case}.png)"}')
    bad += n > 0
sys.exit(1 if bad else 0)
