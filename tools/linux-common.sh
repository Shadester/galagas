#!/usr/bin/env bash
# Helpers for the setup-linux.sh scripts (source this file). Arch Linux and derivatives (CachyOS, EndeavourOS, Manjaro): pacman for the
# official packages, an AUR helper (paru or yay) for the rest. AUR packages are built by the helper, which shows you the PKGBUILD first: read it.
# On another distribution each script stops with the list of what it needs.

die() { echo "error: $*" >&2; exit 1; }

command -v pacman >/dev/null || die "pacman not found: these scripts are for Arch based distributions. Install by hand: $*"

if [ "$(id -u)" = 0 ]; then
    SUDO=
elif command -v sudo >/dev/null; then
    SUDO=sudo
elif command -v pkexec >/dev/null; then
    SUDO=pkexec
else
    die "need root: install sudo or polkit (pkexec)"
fi

# pac PKG...: install the official packages that are not installed yet
pac() {
    local missing=() p
    for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
    [ ${#missing[@]} -eq 0 ] || $SUDO pacman -S --needed "${missing[@]}"
}

# aur PKG...: install the AUR packages that are not installed yet (the helper asks to review the PKGBUILD)
aur() {
    local missing=() p helper
    for p in "$@"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
    [ ${#missing[@]} -eq 0 ] && return 0
    if command -v paru >/dev/null; then helper=paru
    elif command -v yay >/dev/null; then helper=yay
    else die "no AUR helper: install paru (pacman -S paru on CachyOS) or yay, then re-run. Needed from the AUR: ${missing[*]}"
    fi
    if [ -n "$SUDO" ] && [ "$helper" = paru ]; then paru -S --needed --sudo "$SUDO" "${missing[@]}"; else "$helper" -S --needed "${missing[@]}"; fi
}

# gpgkeys ID...: import signing keys (the AUR packages of the GNU toolchain list them in validpgpkeys; makepkg stops without them)
gpgkeys() {
    local k
    for k in "$@"; do gpg --list-keys "$k" >/dev/null 2>&1 || gpg --recv-keys "$k"; done
}

# check TOOL...: print where each tool is
check() {
    echo
    local t
    for t in "$@"; do printf '%-18s %s\n' "$t" "$(command -v "$t" || echo MISSING)"; done
}

# repo venv with the system packages visible (PEP 668: pip cannot install into the system Python). Result: <repo>/.venv
repo_venv() {
    local root=$1
    [ -d "$root/.venv" ] || python3 -m venv --system-site-packages "$root/.venv"
    "$root/.venv/bin/pip" install --quiet "${@:2}"
}
