#!/bin/sh
# Build and run the game in the Gearlynx window. LYNX_BIOS overrides the boot ROM (default lynx/lynxboot.img).
cd "$(dirname "$0")/.." || exit 1
B=${BUILD:-build}
make BUILD="$B" $MAKEARGS >/dev/null || exit 1
BIOS=$(cd "$(dirname "${LYNX_BIOS:-lynxboot.img}")" && pwd)/$(basename "${LYNX_BIOS:-lynxboot.img}")
[ -f "$BIOS" ] || { echo "Boot ROM not found: $BIOS (see README)" >&2; exit 1; }
case $(uname) in
    Darwin) INI="$HOME/Library/Application Support/Geardome/Gearlynx/config.ini"; GL=/Applications/Gearlynx.app/Contents/MacOS/gearlynx ;;
    *)      INI="${XDG_DATA_HOME:-$HOME/.local/share}/Geardome/Gearlynx/config.ini"; GL=gearlynx ;;
esac
[ -x "$GL" ] || GL=gearlynx
if [ -f "$INI" ]; then
    sed -i.bak "s|^BiosPath =.*|BiosPath = $BIOS|" "$INI" && rm -f "$INI.bak"   # Gearlynx has no BIOS flag
else
    echo "No Gearlynx config yet ($INI): set the boot ROM once in its menu ($BIOS); after that this script keeps it." >&2
fi
exec "$GL" -w "$PWD/$B/galaga.lnx"   # -w: window with the menu (Video: scaling)
