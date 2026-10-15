"""Runs an ADF in FS-UAE (a desktop emulator: it can be an A500, an A1200 with AGA, a 68020 / 68030 / 68040) and saves screenshots of its window.
Only the window of FS-UAE is captured (screencapture -l <window id>), never the whole screen; macOS asks once for the permission "Screen Recording".
Needs: brew install --cask fs-uae-emulator, pip install pillow pyobjc-framework-Quartz. Kickstart ROMs are the user's own (~/Documents/FS-UAE/Kickstarts), or the AROS inside FS-UAE for an A500.
Same use as vamiga.py: with Session(adf, 'a1200') as s: s.settle('out.png')"""
import os
import subprocess
import tempfile
import time

import Quartz

EMU = os.environ.get('FSUAE', '/Applications/FS-UAE.app/Contents/MacOS/fs-uae')
KICK = os.path.expanduser('~/Documents/FS-UAE/Kickstarts')
# name: FS-UAE options
MODELS = {
    'a500': ['--amiga_model=A500', '--kickstart_file=' + os.path.join(KICK, 'Kickstart3.1.rom')],                           # OCS, 68000, AROS in FS-UAE
    'a500plus': ['--amiga_model=A500+', '--kickstart_file=internal'],                      # ECS
    'a1200': ['--amiga_model=A1200', '--kickstart_file=' + os.path.join(KICK, 'Kickstart-v3.1-rev-40.68-1993-Commodore-A1200.rom')],     # AGA, 68EC020
    'a1200-030': ['--amiga_model=A1200', '--cpu=68030', '--kickstart_file=' + os.path.join(KICK, 'Kickstart-v3.1-rev-40.68-1993-Commodore-A1200.rom')],
    'a1200-040': ['--amiga_model=A1200', '--cpu=68040', '--kickstart_file=' + os.path.join(KICK, 'Kickstart-v3.1-rev-40.68-1993-Commodore-A1200.rom')],
}


def window_id(pid):
    for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
        if w.get('kCGWindowOwnerPID') == pid and w.get('kCGWindowLayer') == 0 and w['kCGWindowBounds']['Width'] > 200 and w['kCGWindowBounds']['Height'] > 300:
            return w['kCGWindowNumber']
    return None


class Session:
    def __init__(self, adf, model='a1200', size=(960, 720)):
        self.adf, self.model, self.size = adf, model, size

    def __enter__(self):
        self.log = tempfile.NamedTemporaryFile(suffix='.log', delete=False)
        self.p = subprocess.Popen([EMU, *MODELS[self.model], '--floppy_drive_0=' + os.path.abspath(self.adf), '--floppy_drive_speed=0',
                                   '--fullscreen=0', f'--window_width={self.size[0]}', f'--window_height={self.size[1]}', '--floppy_drive_volume=0',
                                   '--stereo_separation=0', '--joystick_port_1=none'], stdout=self.log, stderr=self.log)
        return self

    def __exit__(self, *a):
        self.p.terminate()
        try:
            self.p.wait(10)
        except subprocess.TimeoutExpired:
            self.p.kill()

    def shot(self, path):
        end = time.time() + 30
        wid = None
        while wid is None and time.time() < end:
            wid = window_id(self.p.pid)
            time.sleep(0.5)
        if wid is None:
            raise RuntimeError('no window of FS-UAE')
        subprocess.run(['screencapture', '-x', '-o', f'-l{wid}', path], check=True)

    def settle(self, path, timeout=240, boot=15):
        """Waits until the picture does not change any more (a game that freezes with -DHALT), then saves it."""
        time.sleep(boot)
        end, last, same = time.time() + timeout, None, 0
        tmp = path + '.tmp.png'
        while time.time() < end:
            self.shot(tmp)
            data = open(tmp, 'rb').read()
            same = same + 1 if data == last else 0
            last = data
            if same >= 2:
                break
            time.sleep(2)
        os.replace(tmp, path)
