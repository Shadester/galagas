#!/usr/bin/env python3
"""Print memory of the NES game by label after some frames: tools/dbg.py ROM FRAMES label[:size] ... (cynes, headless).
The labels come from the ld65 label file next to the ROM (galaga.lbl)."""
import os
import re
import sys

import cynes


def labels(lbl):
    return {m.group(2): int(m.group(1), 16) for m in re.finditer(r'al ([0-9A-F]+) \.(\w+)', open(lbl).read())}


def main():
    rom, frames = sys.argv[1], int(sys.argv[2])
    lb = labels(os.path.join(os.path.dirname(rom), 'galaga.lbl'))
    nes = cynes.NES(rom)
    nes.step(frames)
    for a in sys.argv[3:]:
        name, _, size = a.partition(':')
        addr = lb[name] if name in lb else int(name, 16)
        print(name, ' '.join('%02x' % nes[addr + i] for i in range(int(size or 1))))


if __name__ == '__main__':
    main()
