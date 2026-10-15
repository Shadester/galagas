#!/usr/bin/env python3
"""Make docs/ocs-vs-aga-play.png and docs/ocs-vs-aga-title.png: the same game state on an A1200 in OCS mode (-DFORCE_OCS: what an A500 shows) and in AGA mode, side by side, with labels,
and an enlarged piece of each to show the tones. Runs FS-UAE (tests/fsuae.py: it needs the permission Screen Recording; only the window is captured).
Usage: python3 tools/make_aga_compare.py"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.join(ROOT, 'tests'))
import fsuae  # noqa: E402

BAR = 56                                                         # the title bar of the FS-UAE window (retina pixels)


def shot(tag, flags):
    build = os.path.join('build', 'cmp_doc', tag)
    png = os.path.join(ROOT, 'build', 'cmp_doc', tag + '.png')
    if not (os.environ.get('REUSE') and os.path.exists(png)):          # REUSE=1: use the pictures of the last run (only the layout changed)
        shutil.rmtree(os.path.join(ROOT, build), ignore_errors=True)
        subprocess.run(['make', '-C', ROOT, f'BUILD={build}', f'EXTRA_CFLAGS={flags}'], check=True, capture_output=True)
        with fsuae.Session(os.path.join(ROOT, build, 'galaga.adf'), 'a1200') as s:
            s.settle(png, boot=45)
    im = Image.open(png).convert('RGB')
    return im.crop((0, BAR, im.width, im.height)).resize((640, 480), Image.LANCZOS), im.crop((0, BAR, im.width, im.height))


def font(size):
    for f in ('/System/Library/Fonts/Helvetica.ttc', '/System/Library/Fonts/Supplemental/Arial.ttf'):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def sheet(left, right, zoom, out, labels):
    """left, right: the 640 x 480 pictures; zoom: a box (x, y, w, h) of the full-size pictures to enlarge below them."""
    W, H = 1300, 480 + 40 + 330
    img = Image.new('RGB', (W, H), (24, 24, 32))
    d = ImageDraw.Draw(img)
    for i, (pic, lab) in enumerate(zip((left[0], right[0]), labels)):
        x = 10 + i * 650
        img.paste(pic, (x, 40))
        d.text((x, 8), lab, font=font(22), fill=(255, 255, 255))
        if zoom:
            zx, zy, zw, zh = zoom
            z = (left if i == 0 else right)[1].crop((zx, zy, zx + zw, zy + zh)).resize((640, 320), Image.NEAREST)
            img.paste(z, (x, 40 + 480 + 10))
    img.save(out)
    print(out)


AUTO = '-DAUTOPLAY -DTITLE_HOLD=0 -DHALT=950'
play_ocs, play_aga = shot('play_ocs', AUTO + ' -DFORCE_OCS'), shot('play_aga', AUTO)
labels = ('Amiga 500 (OCS): 32 colours, 5 bitplanes', 'Amiga 1200 (AGA): 64 colours, 6 bitplanes')
sheet(play_ocs, play_aga, (640, 340, 560, 280), os.path.join(ROOT, 'docs', 'ocs-vs-aga-play.png'), labels)       # (the bosses and butterflies, enlarged: the tones)
title_ocs, title_aga = shot('title_ocs', '-DFORCE_OCS'), shot('title_aga', '')
sheet(title_ocs, title_aga, (380, 100, 760, 380), os.path.join(ROOT, 'docs', 'ocs-vs-aga-title.png'), labels)
