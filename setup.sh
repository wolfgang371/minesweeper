# Environment setup for building/running the minesweeper on Linux.
#
# CrymbleUI bundles SFML 3.0 + CSFML 3.0 inside its shard. After `shards install`
# they live under lib/crymble-ui/locallib/{sfml3,csfml3}/lib/linux/; this script
# wires those up so the linker and loader can find them.
#
# Usage (source it, from any directory):
#   shards install
#   source setup.sh
#   shards build minesweeper && bin/minesweeper
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRYMBLE="$PROJECT_DIR/lib/crymble-ui"
SFML3="$CRYMBLE/locallib/sfml3"
CSFML3="$CRYMBLE/locallib/csfml3"

# `:-` defaults so this stays safe to `source` under `set -u` (e.g. from
# scripts/build-appimage.sh, where these vars are unset on a fresh CI runner).
export LD_LIBRARY_PATH="$SFML3/lib/linux:$CSFML3/lib/linux:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$SFML3/lib/linux:$CSFML3/lib/linux:${LIBRARY_PATH:-}"
export CSFML_INCLUDE_DIR="$CSFML3/include"
export PKG_CONFIG_PATH="$CSFML3/lib/linux/pkgconfig:${PKG_CONFIG_PATH:-}"
