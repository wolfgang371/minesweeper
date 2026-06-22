# Cross-building a Windows `.exe` from Linux

This produces a **fully-static** `minesweeper.exe` for Windows x86-64 — no DLLs,
no Visual C++ redistributable. It cross-compiles on Linux using the **MSVC**
toolchain (to match crymbleui's vendored SFML3/CSFML3, which are MSVC `/MT`
static libs, including the patched `sfml-graphics.lib` that fixes the Windows
font-garbling bug).

## How it works

```
crystal build src/minesweeper-gui.cr --cross-compile --target x86_64-windows-msvc
        → build/win/minesweeper.obj        (Windows object, on Linux)
lld-link  <obj> <libs...>  (static CRT, /SUBSYSTEM:WINDOWS)
        → build/win/minesweeper.exe        (fully-static GUI exe)
```

Linked libraries come from three places:
1. **crymbleui** — `lib/crymble-ui/locallib/{sfml3,csfml3}/lib/win32/*.lib`
   (vendored MSVC SFML3 + CSFML3, pulled in by `shards install`).
2. **Crystal runtime** — `gc.lib`, `iconv.lib` from the Crystal Windows release
   (matching your local Crystal version).
3. **MSVC CRT + Windows SDK** — `libcmt/libvcruntime/libucrt`, `kernel32`,
   `user32`, `opengl32`, … obtained with [`xwin`](https://github.com/Jake-Shadle/xwin).

(2) and (3) are fetched once by `scripts/win-setup-deps.sh` into
`$WIN_DEPS` (default `~/.cache/win-crossbuild`, outside the repo).

## Prerequisites

- `crystal` (same version used to fetch the Windows runtime libs — handled
  automatically by the setup script).
- LLVM's `lld-link` — `sudo apt install lld`.
- `curl`, `unzip`, network access (for the one-time deps fetch).

## Usage

```sh
shards install              # pulls crymble-ui (+ its vendored Windows libs)
./scripts/win-setup-deps.sh # one-time: downloads xwin SDK + Crystal Windows libs (~hundreds of MB)
./scripts/linux_cross_build_win32.sh   # → build/win/minesweeper.exe
```

Copy `build/win/minesweeper.exe` to any Windows x64 machine and run it — it
needs nothing else.

## Notes

- The exe imports only base-Windows DLLs (`kernel32`, `user32`, `gdi32`,
  `opengl32`, `advapi32`, `shell32`, `ole32`, `winmm`, `ntdll`, `dbghelp`).
  Verify with `objdump -p build/win/minesweeper.exe | grep 'DLL Name'`.
- `$WIN_DEPS` is overridable: `WIN_DEPS=/path ./scripts/win-setup-deps.sh`
  (and the same for `./scripts/linux_cross_build_win32.sh`).
- This is the MSVC route, *not* MinGW. crymbleui ships MSVC libs, so the GNU/
  MinGW approach (used by e.g. the `mincut` project) cannot link them.
