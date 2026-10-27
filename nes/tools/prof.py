#!/usr/bin/env python3
"""Cycles of the game's routines: run the ROM in cynes to a frame, copy the CPU's memory (RAM, battery RAM, the mapped banks) into py65 and
call routines there, counting cycles. The PPU and the APU are not there (their registers read as 0).
    tools/prof.py ROM FRAME routine [routine ...]      (pip install cynes py65; labels from galaga.lbl)"""
import os
import re
import sys

import cynes
from py65.devices.mpu6502 import MPU


def labels(lbl):
    return {m.group(2): int(m.group(1), 16) for m in re.finditer(r'al ([0-9A-F]+) \.(\w+)', open(lbl).read())}


def snapshot(nes):
    mem = bytearray(65536)
    for a in list(range(0, 0x800)) + list(range(0x6000, 0x10000)):
        mem[a] = nes[a]
    return mem


def call(mem, addr, a=0, x=0, y=0, limit=2_000_000):
    """Run the routine at addr (jsr) on a copy of mem; -> cycles."""
    mpu = MPU()
    mpu.memory = bytearray(mem)
    mpu.a, mpu.x, mpu.y = a, x, y
    mpu.sp = 0xf0
    mpu.memory[0x1f1] = 0xff                     # return address $ffff - 1 + 1: stop when pc == $0000? use a marker
    ret = 0xfff0 - 1
    mpu.memory[0x1f1] = ret & 255
    mpu.memory[0x1f2] = ret >> 8
    mpu.sp = 0xf0
    mpu.pc = addr
    start = mpu.processorCycles
    while mpu.pc != 0xfff0:
        mpu.step()
        if mpu.processorCycles - start > limit:
            raise RuntimeError('no return from $%04x' % addr)
    return mpu.processorCycles - start


def main():
    rom, frame = sys.argv[1], int(sys.argv[2])
    lb = labels(os.path.join(os.path.dirname(rom), 'galaga.lbl'))
    nes = cynes.NES(rom)
    nes.step(frame)
    mem = snapshot(nes)
    for name in sys.argv[3:]:
        print('%-20s %6d' % (name, call(mem, lb[name])))


if __name__ == '__main__':
    main()
