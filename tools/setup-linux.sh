#!/usr/bin/env bash
# Set up everything to build and test all the ports on Arch Linux and derivatives (it runs the setup-linux.sh of every port).
# What it cannot do: the Lynx boot ROM (your own dump, lynx/lynxboot.img) and PICO-8 (proprietary: https://www.lexaloffle.com/pico-8.php).
#   tools/setup-linux.sh            all the ports
#   tools/setup-linux.sh nes tui    only those (c64 lynx nes amiga psp thumby tui)
set -euo pipefail
cd "$(dirname "$0")/.."
ports=("$@"); [ ${#ports[@]} -gt 0 ] || ports=(c64 lynx nes tui psp amiga thumby)
for p in "${ports[@]}"; do
    echo; echo "=============== $p"
    "$p/tools/setup-linux.sh"
done
echo
[ -f lynx/lynxboot.img ] || echo "Missing: lynx/lynxboot.img (the Lynx boot ROM, from your own Lynx)"
command -v pico8 >/dev/null || echo "Missing: pico8 (the PICO-8 binary, for pico8/tests and tools/run.sh)"
echo "Tests of the NES and the comparison scripts: use .venv/bin/python (cynes)"
