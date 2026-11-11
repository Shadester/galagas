#!/usr/bin/env python3
"""Wrap a flat, position independent 68000 binary in an AmigaDOS hunk executable (one code hunk, no relocations).
Usage: make_hunk.py IN.bin OUT   (a WHDLoad Slave and the Workbench program are files of this kind)"""
import struct
import sys

code = open(sys.argv[1], 'rb').read()
code += b'\0' * (-len(code) % 4)
n = len(code) // 4
open(sys.argv[2], 'wb').write(struct.pack('>6I', 0x3f3, 0, 1, 0, 0, n) + struct.pack('>2I', 0x3e9, n) + code + struct.pack('>I', 0x3f2))
