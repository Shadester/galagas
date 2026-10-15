#!/usr/bin/env python3
"""Make an ADF (an 880 KB Amiga floppy image) with a bootblock and, after it, the game code and the AGA data (only an AGA machine reads those).
Usage: make_adf.py BOOT.bin [GAME.bin [AGA.bin]] OUT.adf
BOOT.bin is the bootblock (at most 1024 bytes). The checksum is the one the Kickstart checks: the sum of the 256 longs
with the carry added back is 0xFFFFFFFF."""
import struct
import sys

ADF_SIZE = 80 * 2 * 11 * 512


def bootblock(code):
    assert len(code) <= 1024, 'the bootblock is 1024 bytes'
    b = bytearray(code.ljust(1024, b'\0'))
    b[4:8] = b'\0\0\0\0'
    s = 0
    for (v,) in struct.iter_unpack('>I', bytes(b)):
        s += v
        if s > 0xffffffff:
            s = (s & 0xffffffff) + 1
    b[4:8] = struct.pack('>I', ~s & 0xffffffff)
    return bytes(b)


if __name__ == '__main__':
    boot, out = sys.argv[1], sys.argv[-1]
    game = open(sys.argv[2], 'rb').read() if len(sys.argv) >= 4 else b''
    aga = open(sys.argv[3], 'rb').read() if len(sys.argv) == 5 else b''
    code = bytearray(open(boot, 'rb').read())
    size = (len(game) + 511) // 512 * 512      # the bootblock reads whole sectors; its LOADSIZE is at byte 16
    assert len(aga) % 512 == 0
    code[16:20] = struct.pack('>I', size)
    code[20:24] = struct.pack('>I', len(aga))
    code[24:28] = struct.pack('>I', len(aga) + 3 * 56 * 6 * 256 if aga else 0)      # the AGA data, then 3 bitmaps of 6 planes (video.c)
    img = bootblock(bytes(code)) + game.ljust(size, b'\0') + aga
    assert len(img) <= ADF_SIZE, 'the game does not fit on the disk'
    open(out, 'wb').write(img.ljust(ADF_SIZE, b'\0'))
    print(out, len(img), 'bytes used')
