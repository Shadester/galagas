#!/usr/bin/env bash
# Install the tools needed to build and run the game on Arch Linux and derivatives: the 68000 cross compiler (m68k-elf-binutils, m68k-elf-gcc, AUR),
# the FS-UAE emulator (the AROS replacement ROM is inside: no Kickstart needed), Pillow, and for the tests Playwright + Chromium (vAmigaWeb) and, for
# tests/fsuae.py (screenshots of the FS-UAE window), xdotool and ImageMagick.
# The compiler is a chain of four AUR packages and takes a while (gcc is built twice). Say yes when pacman asks to remove m68k-elf-gcc-bootstrap.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/linux-common.sh" m68k-elf-gcc m68k-elf-binutils fs-uae python-pillow

pac base-devel fs-uae python-pillow python-playwright xdotool imagemagick

if ! command -v m68k-elf-gcc >/dev/null; then
    # the signing keys of the GNU sources (binutils, gcc, mpfr, mpc, gmp), as the PKGBUILDs list them in validpgpkeys
    gpgkeys 5EF3A41171BB77E6110ED2D01F3D03348DB1A3E2 738409F520DF9190 \
            D3A93CAD751C2AF4F8C7AD516C35B99309B5FA62 A534BE3F83E241D918280AEB5831D11A0D4DB02A \
            AD17A21EF8AED8F1CC02DBD9F7D5C9BF765C61E3 343C2FF0FBEE5EC2EDBEF399F3599FF828C67298
    aur m68k-elf-binutils m68k-elf-gcc-bootstrap m68k-elf-newlib   # the bootstrap compiler builds newlib, newlib is needed by the real gcc
    aur m68k-elf-gcc                                               # replaces the bootstrap compiler
fi
playwright install chromium

check m68k-elf-gcc m68k-elf-as m68k-elf-objcopy fs-uae python3 make
