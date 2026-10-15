#!/bin/sh
# Run the game as on an Amiga 1200 (68020, AGA): FS-UAE needs a Kickstart 3.x ROM (your own). By default the 3.1 ROM for the A1200 in
# ~/Documents/FS-UAE/Kickstarts (the folder of the FS-UAE launcher); KICKSTART=file uses another one.
cd "$(dirname "$0")/.." || exit 1
ROM=${KICKSTART:-$HOME/Documents/FS-UAE/Kickstarts/Kickstart-v3.1-rev-40.68-1993-Commodore-A1200.rom}
if [ ! -f "$ROM" ]; then
    echo "No Kickstart ROM for the A1200 at $ROM. Use: KICKSTART=/path/to/kickstart-3.x.rom tools/run-aga.sh" >&2
    exit 1
fi
KICKSTART="$ROM" MODEL=A1200 exec tools/run.sh
