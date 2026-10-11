#!/usr/bin/env python3
"""Record scope/docs/gameplay.gif: the scope page (?autoplay&god) in headless Chromium, a screenshot of the scope canvas every 100 ms.
Needs playwright and Pillow. Usage: python3 tools/make_scope_gif.py [seconds]   (the game runs about 6 s before the aliens are in)"""
import functools
import http.server
import io
import os
import sys
import threading

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, '..', '..', 'docs')
OUT = os.path.join(HERE, '..', '..', 'scope', 'docs', 'gameplay.gif')
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 24


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=DOCS))
threading.Thread(target=srv.serve_forever, daemon=True).start()
frames = []
with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={'width': 1000, 'height': 700})
    page.goto('http://127.0.0.1:%d/scope/index.html?autoplay&god' % srv.server_address[1])
    page.wait_for_function('window.__galaga && window.__galaga.ticks > 10')
    for _ in range(int(SECONDS * 10)):
        shot = page.locator('#scopebox').screenshot()
        im = Image.open(io.BytesIO(shot)).convert('RGB')
        frames.append(im.resize((340, 340), Image.LANCZOS))
        page.wait_for_timeout(100)
    b.close()
srv.shutdown()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
pal = frames[0].quantize(64, method=Image.Quantize.MEDIANCUT)
q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
q[0].save(OUT, save_all=True, append_images=q[1:], duration=100, loop=0, optimize=True)
print(len(frames), 'frames,', os.path.getsize(OUT) // 1024, 'KB')
