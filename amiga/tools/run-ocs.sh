#!/bin/sh
# Run the game as on an Amiga 500 (68000, OCS): FS-UAE with the AROS ROM inside it (no Kickstart needed). KICKSTART=file uses a ROM instead.
cd "$(dirname "$0")/.." || exit 1
MODEL=A500 exec tools/run.sh
