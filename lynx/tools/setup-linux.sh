#!/usr/bin/env bash
# Install the tools needed to build and run the game on Arch Linux and derivatives: cc65 and Gearlynx (both AUR), Pillow.
# The Lynx boot ROM is copyrighted: put your own dump at lynx/lynxboot.img (512 bytes, git-ignored).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/linux-common.sh" cc65 gearlynx python-pillow

pac base-devel python-pillow sdl3
aur cc65 gearlynx

BIOS=$ROOT/lynx/lynxboot.img
if [ "$(md5sum "$BIOS" 2>/dev/null | cut -d' ' -f1)" != fcd403db69f54290b51035d82f835e7b ]; then
    echo "lynx/lynxboot.img missing or not the original boot ROM (md5 fcd403db69f54290b51035d82f835e7b)." >&2
fi
check ca65 ld65 gearlynx python3 make
