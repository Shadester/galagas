#!/usr/bin/env python3
"""The rules on the machines: the scripted game of src/selftest.h on an A500 (68000, OCS), an A1200 (68020, AGA), an A1200 with a 68030 and a 68040
in FS-UAE (tests/fsuae.py). The screen turns green if the hash is right, red if not. This tests the detection and the caches of src/hw.s.
Usage: python3 tests/test_hw.py [ticks] [model ...]   (models: see fsuae.MODELS)"""
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import fsuae  # noqa: E402

TICKS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 3000
MODELS = [a for a in sys.argv[1:] if a in fsuae.MODELS] or ['a500', 'a1200', 'a1200-030', 'a1200-040']

build = os.path.join(ROOT, 'build', 'hw_selftest')
shutil.rmtree(build, ignore_errors=True)
os.makedirs(build)
exe = os.path.join(build, 'native')
subprocess.run(['cc', '-O1', '-w', f'-DTICKS={TICKS}', '-I', os.path.join(ROOT, '..', 'psp'), '-I', os.path.join(ROOT, 'src'), '-o', exe,
                os.path.join(HERE, 'selftest_native.c')], check=True)
h = subprocess.run([exe], check=True, capture_output=True, text=True).stdout.strip()
subprocess.run(['make', '-C', ROOT, 'BUILD=build/hw_selftest', f'EXTRA_CFLAGS=-DSELFTEST={TICKS} -DSELFTEST_EXPECT=0x{h}u'], check=True, capture_output=True)


def run(model):
    out = os.path.join(build, model + '.png')
    with fsuae.Session(os.path.join(build, 'galaga.adf'), model) as s:
        time.sleep(20)
        end = time.time() + 400
        while time.time() < end:                         # yellow: the game still runs; green: the hash is right; red: wrong
            s.shot(out)
            im = Image.open(out).convert('RGB')
            r, g, b = im.getpixel((im.width // 2, im.height // 2))
            if g > 100 and r < 60:
                return model, 'PASS'
            if r > 150 and g < 60:
                return model, 'FAIL (red screen: the hash is wrong)'
            time.sleep(3)
    return model, f'FAIL (no result: colour {r},{g},{b})'


with ThreadPoolExecutor(1) as ex:                      # one emulator at a time: FS-UAE windows would overlap
    results = list(ex.map(run, MODELS))
for model, r in results:
    print(f'{r} {model}: {TICKS} ticks, hash {h}')
sys.exit(1 if any(r.startswith('FAIL') for _, r in results) else 0)
