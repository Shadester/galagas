#!/bin/sh
# Copy the game to a Thumby Color that is connected with USB. It goes to /Games/Galaga.
# Installs mpremote (Homebrew, or pipx on Linux) if it is missing. Without mpremote: copy the Galaga folder with the
# Thumby Color Code Editor (https://color.thumby.us/code/) or Thonny.
cd "$(dirname "$0")/../Galaga" || exit 1
if ! command -v mpremote >/dev/null; then
    if command -v brew >/dev/null; then brew install mpremote; else pipx install mpremote; fi || { echo "mpremote not found: brew install mpremote (macOS) or pipx install mpremote" >&2; exit 1; }
fi
mpremote fs mkdir :/Games/Galaga 2>/dev/null
mpremote fs mkdir :/Games/Galaga/jingles 2>/dev/null
for f in manifest.ini main.py game.py view.py sfx.py arcade_data.py sprite_ids.py sprites.bmp beams.bmp title.bmp icon.bmp font.bmp; do
    mpremote fs cp "$f" ":/Games/Galaga/$f" || exit 1
done
for f in jingles/*.rtttl; do
    mpremote fs cp "$f" ":/Games/Galaga/$f" || exit 1
done
echo "Installed: choose Galaga in the launcher."
