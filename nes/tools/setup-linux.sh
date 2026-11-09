#!/usr/bin/env bash
# Install the tools needed to build and test the NES game on Arch Linux and derivatives: cc65 (AUR), Pillow, and a venv (<repo>/.venv) with cynes (the headless
# emulator of the tests) and py65 (tools/prof.py). Run the tests with .venv/bin/python (tests/run.py, ../tools/compare_6502.py nes ...).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/linux-common.sh" cc65 python-pillow cynes py65

pac base-devel python-pillow
aur cc65
repo_venv "$ROOT" cynes py65

check ca65 ld65 python3 make
"$ROOT/.venv/bin/python" -c 'import cynes, py65; print("cynes, py65: ok")'
echo "Use $ROOT/.venv/bin/python for the tests"
