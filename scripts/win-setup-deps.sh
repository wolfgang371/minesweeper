#!/bin/bash
# One-time setup of the Windows cross-build dependencies (Linux host).
#
# Produces, under $WIN_DEPS (default ~/.cache/win-crossbuild):
#   sdk/         — MSVC CRT + Windows SDK import/static libs (via xwin)
#   crystal-win/ — Crystal's Windows runtime libs (gc.lib, iconv.lib, ...)
#
# These, plus crymbleui's vendored MSVC SFML3/CSFML3 libs (pulled in by
# `shards install`) and lld-link, are everything linux_cross_build_win32.sh needs.
#
# Re-running is cheap: each step is skipped if already present.
set -euo pipefail

WIN_DEPS="${WIN_DEPS:-$HOME/.cache/win-crossbuild}"
mkdir -p "$WIN_DEPS"
cd "$WIN_DEPS"

# Match the Crystal runtime libs to the local compiler (ABI must agree).
CRYSTAL_VERSION="$(crystal version | sed -n 's/^Crystal \([0-9.]*\).*/\1/p')"
echo "=== Windows cross-build deps  (Crystal $CRYSTAL_VERSION, WIN_DEPS=$WIN_DEPS) ==="

# --- 1. xwin (fetches/splats the MSVC CRT + Windows SDK) --------------------
if [ ! -x "$WIN_DEPS/xwin/xwin" ]; then
  echo "[1/3] downloading xwin..."
  TAG="$(curl -s https://api.github.com/repos/Jake-Shadle/xwin/releases/latest \
         | grep -oP '"tag_name":\s*"\K[^"]+')"
  curl -sL "https://github.com/Jake-Shadle/xwin/releases/download/${TAG}/xwin-${TAG}-x86_64-unknown-linux-musl.tar.gz" \
       -o xwin.tar.gz
  mkdir -p xwin && tar xzf xwin.tar.gz -C xwin --strip-components=1 && rm -f xwin.tar.gz
else
  echo "[1/3] xwin present"
fi

# --- 2. splat the SDK (x86_64) ---------------------------------------------
if [ ! -d "$WIN_DEPS/sdk/crt/lib/x86_64" ]; then
  echo "[2/3] splatting MSVC CRT + Windows SDK (x86_64, ~hundreds of MB)..."
  "$WIN_DEPS/xwin/xwin" --accept-license --arch x86_64 splat --output "$WIN_DEPS/sdk"
else
  echo "[2/3] SDK already splatted"
fi
# lld-link is case-sensitive on Linux; ensure lowercase aliases exist.
for d in "$WIN_DEPS/sdk/sdk/lib/um/x86_64" "$WIN_DEPS/sdk/sdk/lib/ucrt/x86_64" "$WIN_DEPS/sdk/crt/lib/x86_64"; do
  [ -d "$d" ] || continue
  ( cd "$d"
    for f in *.Lib *.LIB; do
      [ -e "$f" ] || continue
      lc="$(echo "$f" | tr 'A-Z' 'a-z')"
      [ -e "$lc" ] || ln -sf "$f" "$lc"
    done ) 2>/dev/null || true
done

# --- 3. Crystal Windows runtime libs (gc.lib, iconv.lib, ...) ---------------
if [ ! -f "$WIN_DEPS/crystal-win/gc.lib" ]; then
  echo "[3/3] downloading Crystal $CRYSTAL_VERSION Windows libs..."
  # Asset naming differs slightly across releases; try the common variants.
  for url in \
    "https://github.com/crystal-lang/crystal/releases/download/${CRYSTAL_VERSION}/crystal-${CRYSTAL_VERSION}-1-windows-x86_64-msvc-unsupported.zip" \
    "https://github.com/crystal-lang/crystal/releases/download/${CRYSTAL_VERSION}/crystal-${CRYSTAL_VERSION}-windows-x86_64-msvc-unsupported.zip" ; do
    if curl -fsL "$url" -o crystal-win.zip; then break; fi
  done
  [ -f crystal-win.zip ] || { echo "ERROR: could not download Crystal Windows libs"; exit 1; }
  rm -rf crystal-win-extract && mkdir -p crystal-win-extract crystal-win
  unzip -oq crystal-win.zip -d crystal-win-extract
  find crystal-win-extract -iname '*.lib' -exec cp {} crystal-win/ \;
  rm -rf crystal-win.zip crystal-win-extract
else
  echo "[3/3] Crystal Windows libs present"
fi

echo "=== done. Now run ./scripts/linux_cross_build_win32.sh ==="
