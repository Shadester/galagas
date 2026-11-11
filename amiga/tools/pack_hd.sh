#!/bin/sh
# The Amiga game for a hard disk, two archives in build/: galaga-amiga-whdload.lha (the WHDLoad installation) and galaga-amiga-hd.lha (a program with an icon, no WHDLoad).
# Unpack one on the hard disk and click the icon: Galaga (A500, OCS) or GalagaAGA (A1200) in the WHDLoad folder Galaga (WHDLoad is from https://www.whdload.de/), or the program Galaga.
set -e
cd "$(dirname "$0")/.."
make whd exe >/dev/null
D=build/galaga-whdload
rm -rf $D build/galaga-amiga-whdload.lha
mkdir -p $D/Galaga/data
cp build/whd/game.bin $D/Galaga/data/galaga.bin
cp build/whd/aga.bin $D/Galaga/data/galaga.aga
cp build/whd/Galaga.slave build/whd/GalagaAGA.slave $D/Galaga/
python3 tools/make_icon.py $D/Galaga.info drawer
python3 tools/make_icon.py $D/Galaga/Galaga.info project SLAVE=Galaga.slave PRELOAD --tool WHDLoad --stack 10240
python3 tools/make_icon.py $D/Galaga/GalagaAGA.info project SLAVE=GalagaAGA.slave PRELOAD --tool WHDLoad --stack 10240
cat > $D/Galaga/ReadMe <<'EOF'
Galaga for the Amiga (WHDLoad)
==============================
Galaga:     Amiga 500 and up (OCS, ECS, 512 KB chip RAM).
GalagaAGA:  Amiga 1200, 4000 (AGA, 1 MB chip RAM): the game has more colours.
Click the icon. F10 quits at any time; Esc quits on the title screen. The controls are in the game: https://github.com/Shadester/galagas
Needs WHDLoad (https://www.whdload.de/) in C: and a Kickstart 1.3 or newer.
EOF
(cd $D && python3 ../../tools/make_lha.py ../galaga-amiga-whdload.lha Galaga.info Galaga)
rm -rf build/galaga-hd build/galaga-amiga-hd.lha
mkdir build/galaga-hd
cp build/Galaga build/galaga-hd/
python3 tools/make_icon.py build/galaga-hd/Galaga.info tool --stack 4096
(cd build/galaga-hd && python3 ../../tools/make_lha.py ../galaga-amiga-hd.lha Galaga Galaga.info)
ls -l build/galaga-amiga-whdload.lha build/galaga-amiga-hd.lha
