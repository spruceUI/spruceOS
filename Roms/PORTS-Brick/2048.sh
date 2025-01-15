#!/bin/sh

ROM_DIR="$(dirname "$0")"
RA_DIR="/mnt/SDCARD/RetroArch"
CORE_DIR="$ROM_DIR/2048"

cd "$RA_DIR"
./ra64.trimui -v -L "$CORE_DIR/2048_libretro.so"