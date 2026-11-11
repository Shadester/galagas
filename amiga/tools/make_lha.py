#!/usr/bin/env python3
"""Make an LHA archive of folders and files (stored, method -lh0-, header level 0: every Amiga lha reads it; no compression, the lha tools here can only extract).
Usage: make_lha.py OUT.lha PATH...   (run in the folder that holds the paths; folders are added with their contents)"""
import os
import struct
import sys

STAMP = (2026 - 1980) << 25 | 1 << 21 | 1 << 16      # 2026-01-01 00:00: the same archive every time


def crc16(data):
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
    return c


def entry(name, data, method=b'-lh0-'):
    n = name.encode()
    body = method + struct.pack('<IIIBBB', len(data), len(data), STAMP, 0x20, 0, len(n)) + n + struct.pack('<H', crc16(data))
    return bytes([len(body), sum(body) & 255]) + body + data


def walk(path):
    if os.path.isdir(path):
        yield path + '/', None
        for f in sorted(os.listdir(path)):
            yield from walk(path + '/' + f)
    else:
        yield path, open(path, 'rb').read()


if __name__ == '__main__':
    out = b''
    for p in sys.argv[2:]:
        for name, data in walk(p):
            out += entry(name, b'', b'-lhd-') if data is None else entry(name, data)
    open(sys.argv[1], 'wb').write(out + b'\0')
