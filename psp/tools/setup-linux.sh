#!/usr/bin/env bash
# Install the tools needed to build and run the game on Arch Linux and derivatives: PSPSDK (AUR: psp-sdk-bin, the pspdev release in /opt/pspdev),
# PPSSPP, ffmpeg (GIF recording) and Pillow (logo.h).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/tools/linux-common.sh" psp-sdk-bin ppsspp ffmpeg python-pillow

pac base-devel ppsspp ffmpeg python-pillow
aur psp-sdk-bin

echo
echo "Log out and in again, or run:  source /etc/profile.d/pspdev.sh   (PSPDEV=/opt/pspdev and its bin on PATH)"
[ -f /etc/profile.d/pspdev.sh ] && . /etc/profile.d/pspdev.sh
check psp-config psp-gcc PPSSPPSDL ffmpeg make
