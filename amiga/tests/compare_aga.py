#!/usr/bin/env python3
"""The AGA game on an A1200 (6 planes, 64 colours, FMODE 3, no copper scroll) against the OCS game on the same machine (-DFORCE_OCS): at the same tick, every sprite must be in the
same place. The colours are different (the AGA aliens have more tones), so the pictures are compared as masks (a pixel is lit or not). One emulator at a time (tests/fsuae.py).
Usage: python3 tests/compare_aga.py [case ...]"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import fsuae  # noqa: E402

AUTO = '-DAUTOPLAY -DTITLE_HOLD=0'
CASES = {'play130': (AUTO, 130), 'play400': (AUTO, 400), 'play950': (AUTO, 950), 'play1800': (AUTO, 1800), 'chal400': (AUTO + ' -DSTART_STAGE=3', 400), 'late900': (AUTO + ' -DSTART_STAGE=11', 900)}
names = [a for a in sys.argv[1:] if a in CASES] or list(CASES)
out_dir = os.path.join(ROOT, 'build', 'cmp_aga')
os.makedirs(out_dir, exist_ok=True)


def shot(case, ocs):
    flags, halt = CASES[case]
    tag = f'{case}_{"ocs" if ocs else "aga"}'
    build = os.path.join('build', 'cmp_aga', tag)
    shutil.rmtree(os.path.join(ROOT, build), ignore_errors=True)
    subprocess.run(['make', '-C', ROOT, f'BUILD={build}', f'EXTRA_CFLAGS={flags} -DHALT={halt}' + (' -DFORCE_OCS' if ocs else '')], check=True, capture_output=True)
    png = os.path.join(out_dir, tag + '.png')
    with fsuae.Session(os.path.join(ROOT, build, 'galaga.adf'), 'a1200') as s:
        s.settle(png, boot=45)
    return Image.open(png).convert('RGB')


def mask(im):
    return im.convert('L').point(lambda v: 255 if v > 24 else 0)


bad = 0
for case in names:
    a, o = shot(case, False), shot(case, True)
    ma, mo = mask(a), mask(o)
    fat = lambda m: m.filter(ImageFilter.MaxFilter(9))                    # the edges of the shading are not the same: a lit pixel must be near a lit pixel of the other picture
    d = ImageChops.lighter(ImageChops.subtract(ma, fat(mo)), ImageChops.subtract(mo, fat(ma)))
    n = sum(1 for v in (d.get_flattened_data() if hasattr(d, 'get_flattened_data') else d.getdata()) if v)
    print(f'{case}: {"same places" if n < 100 else "DIFFERENT"} ({n} pixels)')
    bad += n >= 100
sys.exit(1 if bad else 0)
