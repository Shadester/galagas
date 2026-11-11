#!/bin/sh
# Run the hard disk versions in FS-UAE: a folder is the hard disk DH0: and the Workbench starts the game. Needs a Kickstart 3.x ROM (KICKSTART=...) and for WHDLoad its C/WHDLoad
# (the archive from https://www.whdload.de/ : WHDLOAD=/path/to/WHDLoad).
#   tools/run-hd.sh exe                        the program Galaga (no WHDLoad)
#   tools/run-hd.sh Galaga | GalagaAGA         the WHDLoad Slave
#   MODEL=A1200 tools/run-hd.sh GalagaAGA      the machine (default A500 for Galaga and exe, A1200 for GalagaAGA; the Kickstart ROMs are in ~/Documents/FS-UAE/Kickstarts)
cd "$(dirname "$0")/.." || exit 1
WHAT=${1:-exe}
tools/pack_hd.sh >/dev/null || exit 1
HD=$(mktemp -d); trap 'rm -rf "$HD"' EXIT
mkdir -p "$HD/S" "$HD/C"
if [ "$WHAT" = exe ]; then
    (cd "$HD" && lha xq "$OLDPWD/build/galaga-amiga-hd.lha")
    echo "DH0:Galaga" > "$HD/S/Startup-Sequence"
else
    [ -f "$WHDLOAD" ] || { echo "WHDLOAD=/path/to/C/WHDLoad is needed" >&2; exit 1; }
    cp "$WHDLOAD" "$HD/C/WHDLoad"
    (cd "$HD" && lha xq "$OLDPWD/build/galaga-amiga-whdload.lha")
    echo "C:WHDLoad DH0:Galaga/$WHAT.slave" > "$HD/S/Startup-Sequence"
fi
case $WHAT in *AGA) DEFMODEL=A1200;; *) DEFMODEL=A500;; esac
if [ -x /Applications/FS-UAE.app/Contents/MacOS/fs-uae ]; then EMU=/Applications/FS-UAE.app/Contents/MacOS/fs-uae; else EMU=${EMULATOR:-fs-uae}; fi
MODEL=${MODEL:-$DEFMODEL}
case $MODEL in A500*) ROM=Kickstart3.1.rom;; *) ROM=Kickstart-v3.1-rev-40.68-1993-Commodore-A1200.rom;; esac
KICK=${KICKSTART:-$HOME/Documents/FS-UAE/Kickstarts/$ROM}
"$EMU" --amiga_model="$MODEL" --kickstart_file="$KICK" --hard_drive_0="$HD" --hard_drive_0_label=DH0 \
    --fullscreen=0 --window_width=960 --window_height=720 --joystick_port_1=none
