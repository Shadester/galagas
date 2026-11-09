#!/bin/sh
# Build EBOOT.PBP (if sources changed) and run it in PPSSPP. Usage: run.sh
# PPSSPP=/path/to/binary overrides the emulator.
cd "$(dirname "$0")/.." || exit 1
make >/dev/null || exit 1
if [ -z "$PPSSPP" ]; then
    MAC=/Applications/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL
    if [ -x "$MAC" ]; then PPSSPP=$MAC; else PPSSPP=$(command -v PPSSPPSDL || command -v ppsspp) || { echo "PPSSPP not found (pacman -S ppsspp, or PPSSPP=/path)" >&2; exit 1; }; fi
fi
exec "$PPSSPP" "$PWD/EBOOT.PBP"
