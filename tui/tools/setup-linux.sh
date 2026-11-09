#!/usr/bin/env bash
# Install the tools for the terminal game, the browser versions and the oscilloscope on Arch Linux and derivatives: Rust (rustup, stable, the wasm32 target),
# Pillow and pyte (the GIF scripts), Playwright + Chromium (tests/test_web.py, test_scope.py).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/linux-common.sh" rustup python-pillow python-pyte python-playwright

pac base-devel rustup python-pillow python-pyte python-numpy python-playwright
rustup default stable
rustup target add wasm32-unknown-unknown
playwright install chromium

check cargo rustc python3
rustup target list --installed
