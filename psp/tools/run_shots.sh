#!/bin/sh
# Debug: build an AUTOPLAY EBOOT, run it in PPSSPP (software renderer so VRAM is readable) and
# leave BMP frames in ~/.config/ppsspp/PSP/shots. Usage: run_shots.sh "<extra cflags>" [seconds]
cd "$(dirname "$0")/.." || exit 1
INI=$HOME/.config/ppsspp/PSP/SYSTEM/ppsspp.ini
rm -f main.o game.o; make EXTRA_CFLAGS="-DAUTOPLAY $1" 2>&1 | grep -E "warning|error"
T=${TMPDIR:-/tmp}/
MAC=/Applications/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL
if [ -x "$MAC" ]; then PPSSPP=$MAC; else PPSSPP=$(command -v PPSSPPSDL || command -v ppsspp) || { echo "PPSSPP not found" >&2; exit 1; }; fi
cp EBOOT.PBP "${T}auto.PBP"; cp "$INI" "${T}ppsspp.ini.bak"
sed -i.bak 's/^SoftwareRenderer = False/SoftwareRenderer = True/' "$INI" && rm -f "$INI.bak"
rm -rf "$HOME/.config/ppsspp/PSP/shots"
"$PPSSPP" "${T}auto.PBP" >/dev/null 2>&1 &
sleep "${2:-25}"; pkill -f -i ppsspp; sleep 1
cp "${T}ppsspp.ini.bak" "$INI"
ls "$HOME/.config/ppsspp/PSP/shots" | wc -l
