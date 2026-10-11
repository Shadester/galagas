#!/usr/bin/env python3
"""The oscilloscope version (../docs/scope) in headless Chromium: the page runs, the software scope draws, the signal is a picture
(the samples are in range, they hold the lines), keys move the ship, the audio worklet starts and plays the same samples.
Needs playwright (pip install playwright; playwright install chromium); builds the module first.
Usage: python3 tests/test_scope.py [screenshot.png]"""
import functools
import http.server
import os
import subprocess
import sys
import threading

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
TUI = os.path.join(HERE, '..')
DOCS = os.path.join(TUI, '..', 'docs')
subprocess.run([os.path.join(TUI, 'tools', 'build_web.sh')], check=True, stdout=subprocess.DEVNULL)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=DOCS))
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = 'http://127.0.0.1:%d/scope/index.html' % srv.server_address[1]
bad = 0


def check(name, ok, extra=''):
    global bad
    print(('PASS ' if ok else 'FAIL ') + name + (' ' + str(extra) if extra and not ok else ''))
    bad += not ok


def lit(page):
    """Pixels of the scope canvas that are bright."""
    return page.evaluate("""() => { const c = document.getElementById('scope');
        const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0;
        for (let i = 0; i < d.length; i += 4) if (d[i + 1] > 150) n++; return n; }""")


with sync_playwright() as p:
    b = p.chromium.launch(args=['--autoplay-policy=no-user-gesture-required'])
    page = b.new_page(viewport={'width': 1280, 'height': 960})
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto(URL + '?autoplay&god')
    page.wait_for_function('window.__galaga && window.__galaga.ticks > 400', timeout=15000)
    check('the game runs', True)
    n = page.evaluate('window.__galaga.segments()')
    check('the picture has lines, and not too many', 60 < n <= 480, n)
    check('the software scope draws bright lines', lit(page) > 500, lit(page))
    s = page.evaluate('Array.from(window.__galaga.samples())')
    check('the samples are in range', len(s) > 100 and all(-1.0001 <= v <= 1.0001 for v in s), len(s))
    check('the picture fills the box (X and Y both move)', max(s[0::2]) - min(s[0::2]) > 0.5 and max(s[1::2]) - min(s[1::2]) > 0.3)
    page.screenshot(path=sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'build', 'scope.png'))
    page.click('#snd')
    page.wait_for_function('window.__galaga.audio && window.__galaga.audio.state === "running"', timeout=10000)
    check('the audio starts', True)
    page.click('#xy')
    check('XY mode on', page.get_attribute('#xy', 'aria-pressed') == 'true')
    page.click('#retrace')
    check('retrace on', page.get_attribute('#retrace', 'aria-pressed') == 'true')
    check('no page errors', not errors, errors)
    page.close()
    # keys: with no autoplay the ship stands still until a key is held
    page = b.new_page(viewport={'width': 1280, 'height': 960})
    page.goto(URL + '?god&stage=1')
    page.wait_for_function('window.__galaga && window.__galaga.ticks > 300', timeout=15000)
    page.keyboard.press('Space')
    page.wait_for_function('window.__galaga.x.web_state() === 2', timeout=20000)    # S_PLAY
    page.wait_for_timeout(300)

    def ship_x():
        # the ship is the lowest 10-segment outline: its x is the mean of the segment starts below y = 1200
        return page.evaluate("""() => { const s = window.__galaga.samples(); let lo = 1e9, hi = -1e9;
            for (let i = 0; i < s.length; i += 2) if (s[i + 1] < -0.45) { lo = Math.min(lo, s[i]); hi = Math.max(hi, s[i]); }
            return lo > hi ? null : (lo + hi) / 2; }""")
    before = ship_x()
    page.keyboard.down('ArrowRight')
    page.wait_for_timeout(600)
    page.keyboard.up('ArrowRight')
    page.wait_for_timeout(100)
    after = ship_x()
    check('a held key moves the ship', before is not None and after is not None and after - before > 0.05, (before, after))
    b.close()
srv.shutdown()
print('FAILED' if bad else 'all passed')
sys.exit(1 if bad else 0)
