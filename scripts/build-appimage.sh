#!/usr/bin/env bash
# ============================================================================
# Linux release build for Minesweeper — produces a portable AppImage with the
# full non-system dependency closure (CrymbleUI's vendored SFML 3 / CSFML 3) and
# a multi-size app icon bundled. The Linux counterpart of
# linux_cross_build_win32.sh.
#
#   Output: build/minesweeper-linux-x86_64.AppImage
#
# Prerequisites:
#   1. crystal + `shards install` already run.
#   2. ImageMagick (convert/identify), patchelf, file — for icon extraction and
#      the dependency-bundling that linuxdeploy performs.
#   3. Network access: linuxdeploy + appimagetool are downloaded on first run
#      (they are themselves AppImages).
#
# Everything this script produces lives under build/ (gitignored), so a build
# leaves NOTHING behind in the working tree. This is the exact build the Release
# workflow (.github/workflows/release.yml) runs on a v* tag.
# ============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

OUT="build"
APPDIR="$OUT/AppDir"
ICO="resources/minesweeper.ico"   # canonical app icon (square 16…256)
APPIMAGE="$OUT/minesweeper-linux-x86_64.AppImage"

rm -rf "$APPDIR"
mkdir -p "$OUT"

# linuxdeploy + appimagetool are AppImages; GitHub runners ship no FUSE, so run
# them via their built-in extract-and-run path instead.
export APPIMAGE_EXTRACT_AND_RUN=1

# 1) Wire the vendored SFML 3 / CSFML 3 paths (LD_LIBRARY_PATH) so both the
#    linker and `ldd` (which linuxdeploy walks) resolve them.
# shellcheck source=/dev/null
source setup.sh

# 2) Build the release binary. NOT --static: the C/SFML deps are bundled into the
#    AppImage instead, and a fully static GUI binary is fragile on Linux anyway.
shards build minesweeper --release --no-debug

# 3) Fetch linuxdeploy (assembles the AppDir) + appimagetool (packs it). Cached
#    across local re-runs. linuxdeploy walks ldd, copies the dependency closure into
#    the AppDir, patches RPATHs, and honours the AppImage excludelist — so host
#    libraries (libGL, libX11, libxcb, the GL driver stack) are deliberately NOT
#    bundled.
fetch() { [ -f "$OUT/$1" ] || wget -qO "$OUT/$1" "$2"; chmod +x "$OUT/$1"; }
fetch linuxdeploy  https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage

# 4) Multi-size desktop icons, extracted from the .ico's matching frames
#    (no scaling/distortion — every standard size is already present).
for px in 16 24 32 48 64 128 256; do
    frame=$(identify -format '%p %w\n' "$ICO" | awk -v w="$px" '$2==w{print $1; exit}')
    [ -n "$frame" ] || continue
    dir="$APPDIR/usr/share/icons/hicolor/${px}x${px}/apps"
    mkdir -p "$dir"
    convert "${ICO}[$frame]" "$dir/minesweeper.png"
done
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/minesweeper.png" "$OUT/minesweeper.png"

# 5) Assemble the AppDir (deps + RPATHs + AppRun + desktop/icon at the root).
"$OUT/linuxdeploy" \
    --appdir "$APPDIR" \
    --executable bin/minesweeper \
    --desktop-file resources/minesweeper.desktop \
    --icon-file "$OUT/minesweeper.png"

# linuxdeploy points the AppDir's root icon (→ appimagetool's .DirIcon, i.e. the
# file-manager thumbnail) at the 64x64 frame; repoint it at 256x256 so it stays crisp.
ln -sf usr/share/icons/hicolor/256x256/apps/minesweeper.png "$APPDIR/minesweeper.png"

# 6) Pack the AppImage under the stable, version-less name a download link can
#    track (/releases/latest/download/minesweeper-linux-x86_64.AppImage); the
#    version stays visible in the GitHub Release title.
"$OUT/appimagetool" "$APPDIR" "$APPIMAGE"

echo "OK: $APPIMAGE built ($(du -h "$APPIMAGE" | cut -f1))."
