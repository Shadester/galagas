#!/usr/bin/env python3
"""Record docs/gameplay.gif: the title screen, then the autoplay build (stage intro, fly-in, dives, shooting; the ship cannot be hit: GODMODE).

Runs headless cynes and keeps a picture every few frames. Needs Pillow and cynes.
Usage: python3 tools/make_gif.py [frames] [step]
"""
import os
import subprocess
import sys

import cynes
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
LAST = int(sys.argv[1]) if len(sys.argv) > 1 else 1500       # NES frames of the autoplay part
STEP = int(sys.argv[2]) if len(sys.argv) > 2 else 4          # NES frames (1/60 s each) per GIF frame
TITLE = 140                                                  # NES frames of the title screen
SCALE = 2


def build(name, flags):
    out = f'build/gif/{name}'
    defs = ' '.join(f'-D {f}' for f in flags.split())
    subprocess.run(['make', '-C', ROOT, f'BUILD={out}', f'CAFLAGS={defs}'], check=True, stdout=subprocess.DEVNULL)
    return os.path.join(ROOT, out, 'galaga.nes')


def record(rom, frames, skip):
    nes = cynes.NES(rom)
    nes.step(skip)
    imgs = []
    for _ in range(frames // STEP):
        fb = nes.step(STEP)
        imgs.append(Image.fromarray(fb).convert('RGB'))
    return imgs


os.makedirs(os.path.join(ROOT, 'build', 'gif'), exist_ok=True)
os.chdir(ROOT)
imgs = record(build('title', ''), TITLE, 20) + record(build('play', 'AUTOPLAY=1 GODMODE=1'), LAST, 30)
imgs = [im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST) for im in imgs]
os.makedirs('docs', exist_ok=True)
OUT = 'docs/gameplay.gif'
imgs[0].save(OUT, save_all=True, append_images=imgs[1:], duration=round(STEP * 1000 / 60), loop=0, optimize=True)
print(len(imgs), 'frames,', os.path.getsize(OUT) // 1024, 'KB')
