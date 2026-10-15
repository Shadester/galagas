#!/bin/sh
# Refresh the GitHub release "latest" with the binaries of all the ports (it is replaced after every push: one release, always the newest files).
#   tools/release.sh            build, collect and publish
#   DRYRUN=1 tools/release.sh   collect only, list the files (nothing is published)
# Needs: gh (logged in), m68k-elf-gcc for the Amiga disk, c1541 (VICE) for the C64 disk, zip. It refuses to run when a tracked file is changed or a commit is not pushed:
# the release must be what is on GitHub.
set -e
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then echo "tracked files are changed: commit first" >&2; exit 1; fi
if [ -n "$(git rev-list @{u}..HEAD 2>/dev/null)" ]; then echo "there are commits that are not pushed: push first" >&2; exit 1; fi
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
add() { [ -f "$1" ] && cp "$1" "$OUT/$2" || echo "missing: $1" >&2; }

make -C amiga >/dev/null                                   # build/galaga.adf (the disk image: the game and the AGA data)
add amiga/build/galaga.adf galaga-amiga.adf
add amiga/docs/galaga.adz galaga-amiga.adz
add docs/psp/EBOOT.PBP EBOOT.PBP
mkdir -p "$OUT/psp/PSP/GAME/PSPGALAGA" && cp docs/psp/EBOOT.PBP "$OUT/psp/PSP/GAME/PSPGALAGA/" && (cd "$OUT/psp" && zip -qr ../galaga-psp.zip PSP) && rm -rf "$OUT/psp"
add c64/docs/galaga.prg galaga-c64.prg
if command -v c1541 >/dev/null; then c1541 -format "galaga,01" d64 "$OUT/galaga-c64.d64" -write c64/docs/galaga.prg galaga >/dev/null; else echo "no c1541: no D64" >&2; fi
add docs/lynx/galaga.lnx galaga-lynx.lnx
add docs/lynx/galaga-portrait.lnx galaga-lynx-portrait.lnx
add pico8/galaga.p8 galaga-pico8.p8
add docs/tui/galaga.wasm galaga.wasm                       # (the terminal and the oscilloscope pages play the same module)

ls -l "$OUT" | sed 1d
[ -n "$DRYRUN" ] && exit 0
SHA=$(git rev-parse HEAD)
NOTES="The binaries of commit $SHA ($(git log -1 --format=%s)).

- Amiga: galaga-amiga.adf (a disk for an Amiga 500 or 1200, FS-UAE, a floppy emulator), galaga-amiga.adz (gzipped: vAmigaWeb)
- PSP: galaga-psp.zip (copy the folder PSP to the memory stick) or EBOOT.PBP alone
- C64: galaga-c64.prg, galaga-c64.d64
- Atari Lynx: galaga-lynx.lnx, galaga-lynx-portrait.lnx
- PICO-8: galaga-pico8.p8
- Terminal and oscilloscope: galaga.wasm (WebAssembly: the game for the play pages)"
gh release delete latest --cleanup-tag --yes >/dev/null 2>&1 || true
gh release create latest "$OUT"/* --title "Latest builds" --notes "$NOTES" --target "$SHA" --latest
