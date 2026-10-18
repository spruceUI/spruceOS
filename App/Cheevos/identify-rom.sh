#!/bin/sh
# Identify a ROM's RetroAchievements game for Spruce's game menu ("View achievement progress"):
#
#   identify-rom.sh --path /mnt/SDCARD/Roms/GBA/game.zip --work-dir <scratch dir> --json
#
# Prints one JSON object (see cheevos/platform/identify_rom.py). This script only sets up
# Spruce's app environment contract and starts the headless helper: no UI, no app start-up.
# It uses RAOfflineProxy's hashing wrapper without changing the proxy, which locates its own
# native library, so no library path is added here.

# appEnv.sh exports SPRUCE_PLATFORM, SPRUCE_PYTHON and SSL_CERT_FILE. Anything it prints goes to
# stderr: stdout carries only the helper's JSON.
# shellcheck source=/dev/null
. /mnt/SDCARD/spruce/scripts/appEnv.sh >&2

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
export PLATFORM="$SPRUCE_PLATFORM"
export PYTHONPATH="$APP_DIR"

# Python puts the working directory on sys.path for -m: use our own, not the caller's.
cd "$APP_DIR" || exit 1
exec "$SPRUCE_PYTHON" -m cheevos.platform.identify_rom "$@"
