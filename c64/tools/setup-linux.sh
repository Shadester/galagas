#!/usr/bin/env bash
# Install the tools needed to build and run the game on Arch Linux and derivatives: acme (assembler), VICE (x64sc, c1541), Exomizer (PRG compressor), Pillow.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/linux-common.sh" acme vice exomizer python-pillow

pac base-devel acme vice python-pillow

if ! command -v exomizer >/dev/null; then
    # The AUR package downloads from a Bitbucket address that is gone (404). Try it; if it fails, build the Exomizer sources from Bitbucket (into ~/.local/bin).
    if ! aur exomizer; then
        echo "AUR build of exomizer failed: building the Bitbucket master archive into ~/.local/bin" >&2
        T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
        curl -fsSL -o "$T/exo.zip" https://bitbucket.org/magli143/exomizer/get/master.zip
        unzip -q "$T/exo.zip" -d "$T"
        make -C "$T"/magli143-exomizer-*/src >/dev/null
        install -Dm755 "$T"/magli143-exomizer-*/src/exomizer "$HOME/.local/bin/exomizer"
        case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "add ~/.local/bin to your PATH" >&2 ;; esac
    fi
fi

check acme x64sc exomizer c1541 python3 make
