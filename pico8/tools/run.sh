#!/bin/sh
# Run the cart in PICO-8 in a window. Extra arguments go to PICO-8, e.g. -p "autoplay stage=3" (see README).
# PICO8=/path/to/pico8 overrides the binary.
cd "$(dirname "$0")/.." || exit 1
MAC=/Applications/PICO-8.app/Contents/MacOS/pico8
[ -z "$PICO8" ] && { command -v pico8 >/dev/null && PICO8=pico8 || PICO8=$MAC; }
exec "$PICO8" -windowed 1 -run galaga.p8 "$@"
