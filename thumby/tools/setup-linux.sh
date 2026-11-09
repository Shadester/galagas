#!/usr/bin/env bash
# Build the Thumby Color game engine for the desktop (TinyCircuits' MicroPython fork, Unix port, SDL2 window) on Arch Linux and derivatives, so the game
# runs and is tested without a device. Result: build/mp-thumby/ports/unix/build-standard/micropython. Also: mpremote (tools/install.sh), Pillow.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(cd .. && pwd)
. "$ROOT/tools/linux-common.sh" sdl2 libffi pkgconf python-pillow git

pac base-devel git sdl2 libffi pkgconf python-pillow python-pipx
command -v mpremote >/dev/null || pipx install mpremote

mkdir -p build
[ -d build/mp-thumby ] || git clone --branch engine --depth 1 https://github.com/TinyCircuits/micropython.git build/mp-thumby
cd build/mp-thumby
git submodule update --init --depth 1 TinyCircuits-Tiny-Game-Engine
(cd TinyCircuits-Tiny-Game-Engine && git submodule update --init --recursive --depth 1)

# -Wno-error: a newer gcc warns about code that MicroPython compiles with -Werror (the macOS script does the same for clang)
make -C mpy-cross -j"$(nproc)" CFLAGS_EXTRA="-Wno-error"
cd ports/unix
make submodules
make -j"$(nproc)" USER_C_MODULES=../../TinyCircuits-Tiny-Game-Engine CFLAGS_EXTRA="-Wno-error"

echo
ls -l build-standard/micropython
