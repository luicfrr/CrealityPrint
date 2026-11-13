#!/bin/bash
# Build the CrealityPrint Flatpak on Fedora without sudo, with the flatpak-builder Flatpak
# (org.flatpak.Builder). The GNOME SDK and the LLVM extension come from Flathub on first run.
#
# Everything this writes lives under $WORK (default ~/.cache/crealityprint-flatpak); delete that
# folder to reclaim the space. The result is a bundle; it is not installed:
#   flatpak install --user "$WORK/CrealityPrint-dev.flatpak"
#
# JOBS limits parallel compile jobs (default 4): with 16 GB of RAM, more than that runs out of memory
# on the OpenCV, OCCT and CGAL sources.
set -euo pipefail

cd "$(dirname "$0")"
WORK="${WORK:-$HOME/.cache/crealityprint-flatpak}"
JOBS="${JOBS:-4}"
mkdir -p "$WORK"

flatpak run org.flatpak.Builder \
    --user \
    --install-deps-from=flathub \
    --jobs="$JOBS" \
    --ccache \
    --state-dir="$WORK/state" \
    --repo="$WORK/repo" \
    --force-clean \
    "$WORK/build" \
    io.github.crealityofficial.CrealityPrint.yml

flatpak build-bundle "$WORK/repo" "$WORK/CrealityPrint-dev.flatpak" io.github.crealityofficial.CrealityPrint
echo "Bundle: $WORK/CrealityPrint-dev.flatpak"
