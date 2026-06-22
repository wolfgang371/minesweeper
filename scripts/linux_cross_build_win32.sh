#!/bin/bash
# Cross-build a fully-static Windows x86-64 minesweeper.exe from Linux.
#
# Toolchain (all on the Linux host):
#   crystal --cross-compile --target x86_64-windows-msvc   → minesweeper.obj
#   lld-link  (static CRT)                                  → minesweeper.exe
#
# The .exe is "fat": it links the static CRT (/MT, matching crymbleui's
# vendored SFML3) and statically embeds SFML3/CSFML3/freetype, so it depends
# only on base-Windows DLLs (kernel32, user32, gdi32, opengl32, ...). No VC++
# redistributable, no SFML DLLs.
#
# Prerequisites (one-time):  ./scripts/win-setup-deps.sh   then   shards install
set -euo pipefail

# Run from the repository root (this script lives in scripts/).
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WIN_DEPS="${WIN_DEPS:-$HOME/.cache/win-crossbuild}"
SRC="src/minesweeper-gui.cr"
OUT="build/win/minesweeper.exe"
OBJ="build/win/minesweeper"

# crymbleui's vendored MSVC SFML3/CSFML3 libs (populated by `shards install`)
CRYM="lib/crymble-ui/locallib"
SFML_WIN="$CRYM/sfml3/lib/win32"
CSFML_WIN="$CRYM/csfml3/lib/win32"

# Windows SDK / CRT (from xwin) + Crystal runtime libs (from win-setup-deps.sh)
SDK_CRT="$WIN_DEPS/sdk/crt/lib/x86_64"
SDK_UCRT="$WIN_DEPS/sdk/sdk/lib/ucrt/x86_64"
SDK_UM="$WIN_DEPS/sdk/sdk/lib/um/x86_64"
CRYSTAL_WIN="$WIN_DEPS/crystal-win"

echo "=== Building $OUT (x86_64-windows-msvc, fully static) ==="

# --- prerequisite checks ----------------------------------------------------
command -v lld-link-18 >/dev/null 2>&1 || command -v lld-link >/dev/null 2>&1 || {
  echo "ERROR: lld-link not found (install LLVM's lld, e.g. 'apt install lld')"; exit 1; }
LLD="$(command -v lld-link-18 || command -v lld-link)"

[ -f "$SFML_WIN/sfml-graphics.lib" ] || {
  echo "ERROR: crymbleui Windows libs missing at $SFML_WIN"
  echo "       run 'shards install' first (pulls crymble-ui with its vendored libs)"; exit 1; }

[ -f "$CRYSTAL_WIN/gc.lib" ] && [ -d "$SDK_UM" ] || {
  echo "ERROR: Windows cross-build deps missing under $WIN_DEPS"
  echo "       run ./scripts/win-setup-deps.sh first"; exit 1; }

# --- 1. cross-compile Crystal → Windows object ------------------------------
echo "[1/2] cross-compiling $SRC ..."
mkdir -p build/win
crystal build "$SRC" --cross-compile --target x86_64-windows-msvc -o "$OBJ"
[ -f "$OBJ.obj" ] || { echo "ERROR: cross-compile produced no $OBJ.obj"; exit 1; }

# --- 2. link with lld-link (static CRT) -------------------------------------
echo "[2/2] linking $OUT ..."
"$LLD" /nologo "$OBJ.obj" /OUT:"$OUT" \
  /INCREMENTAL:NO /STACK:0x800000 /SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup \
  /NODEFAULTLIB:msvcrt.lib /NODEFAULTLIB:vcruntime.lib /NODEFAULTLIB:ucrt.lib \
  /LIBPATH:"$SFML_WIN" /LIBPATH:"$CSFML_WIN" /LIBPATH:"$CRYSTAL_WIN" \
  /LIBPATH:"$SDK_CRT" /LIBPATH:"$SDK_UCRT" /LIBPATH:"$SDK_UM" \
  opengl32.lib advapi32.lib user32.lib winmm.lib gdi32.lib freetype.lib \
  sfml-graphics.lib sfml-window.lib sfml-system.lib \
  csfml-graphics.lib csfml-window.lib csfml-system.lib \
  gc.lib ntdll.lib iconv.lib \
  libcmt.lib libvcruntime.lib libucrt.lib \
  shell32.lib ole32.lib ws2_32.lib kernel32.lib legacy_stdio_definitions.lib dbghelp.lib

rm -f "$OBJ.obj"
echo
echo "=== Done: $OUT ($(du -h "$OUT" | cut -f1)) ==="
file "$OUT"
echo "Fully static — copy to any Windows x64 and run. No DLLs/redistributable needed."
