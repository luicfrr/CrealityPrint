#!/bin/bash
# Build the CrealityPrint Flatpak on Fedora without sudo, with the flatpak-builder Flatpak
# (org.flatpak.Builder). The GNOME SDK and the LLVM extension come from Flathub on first run.
#
# Everything this writes lives under $WORK (default ~/.cache/crealityprint-flatpak); delete that
# folder to reclaim the space. The result is a bundle; it is not installed:
#   flatpak install --user "$WORK/CrealityPrint-dev.flatpak"
#
# JOBS is the most compile jobs at once, inside each dependency's build too (default 4). A job of OpenCV,
# OCCT or CGAL takes 2-4 GB: JOBS=1 peaks around 4 GB, JOBS=4 around 14 GB.
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
