#!/usr/bin/env bash
# iPhone tools (libimobiledevice stack) + MVT. Run as your normal user:
#   ./mvt/install.sh            install / update, then check every tool
#   ./mvt/install.sh --rebuild  also rebuild idevicerestore from the latest upstream
# Safe to re-run. Libraries stay on the official-repo versions (see README.md).
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user (sudo is used where needed)."; exit 1; }

step() { printf '\n:: %s\n' "$*"; }
rebuild=false; [ "${1:-}" = "--rebuild" ] && rebuild=true

repo_pkgs=(libplist libimobiledevice-glue libusbmuxd usbmuxd libtatsu libimobiledevice ifuse)
aur_pkgs=(libirecovery libideviceactivation ideviceinstaller-git)

step "Libraries: official-repo versions, not -git ones"
# A -git libplist changes the library version and breaks upower, usbmuxd and ifuse
git_libs=$(pacman -Qq libplist-git libimobiledevice-glue-git libimobiledevice-git \
    libusbmuxd-git usbmuxd-git libtatsu-git libirecovery-git 2>/dev/null || true)
if [ -n "$git_libs" ]; then
    echo "   replacing: $git_libs"
    sudo pacman -Rdd --noconfirm $git_libs
fi

step "Packages (official repos)"
sudo pacman -S --needed "${repo_pkgs[@]}"

step "Packages (AUR, via paru)"
paru -S --needed "${aur_pkgs[@]}"

step "idevicerestore (built from git: the 1.0.0 release no longer builds)"
if $rebuild || ! pacman -Q idevicerestore-git >/dev/null 2>&1; then
    build=$(mktemp -d)
    cp idevicerestore-git/* "$build/"
    (cd "$build" && makepkg -sif --noconfirm)
    rm -rf "$build"
else
    echo "   already installed ($(pacman -Q idevicerestore-git)); --rebuild to update"
fi

step "pacman: don't let paru swap idevicerestore-git for the AUR one"
if ! grep -qE '^IgnorePkg\s*=.*\bidevicerestore-git\b' /etc/pacman.conf; then
    if grep -qE '^IgnorePkg\s*=' /etc/pacman.conf; then
        sudo sed -i -E 's/^(IgnorePkg\s*=.*)$/\1 idevicerestore-git/' /etc/pacman.conf
    else
        sudo sed -i -E 's/^#\s*IgnorePkg\s*=.*$/IgnorePkg = idevicerestore-git/' /etc/pacman.conf
    fi
fi
grep -E '^IgnorePkg' /etc/pacman.conf

step "MVT (Mobile Verification Toolkit), via uv"
uv tool install --upgrade mvt

step "Check: every tool finds its libraries and runs"
ok=true
for b in ideviceinfo ideviceinstaller irecovery idevicerestore ideviceactivation ifuse usbmuxd mvt-ios; do
    path=$(command -v "$b" 2>/dev/null) || { echo "   MISSING: $b"; ok=false; continue; }
    if ldd "$path" 2>/dev/null | grep -q 'not found'; then
        echo "   BROKEN:  $b"; ok=false
    else
        printf '   ok:      %-18s %s\n' "$b" "$("$b" --version 2>&1 | head -1)"
    fi
done
$ok || { echo ":: Some tools are missing or broken (see above)."; exit 1; }

echo ":: Done. Plug in the iPhone, unlock it, tap Trust, then: idevice_id -l && idevicepair validate"
