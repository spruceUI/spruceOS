#!/bin/sh

ROM_DIR="$(dirname "$0")"
RA_DIR="/mnt/SDCARD/RetroArch"
DINO_DIR="$RA_DIR/.retroarch/downloads/dinothawr"
CORE_DIR="$RA_DIR/.retroarch/cores"

cd "$RA_DIR"

./ra32.miyoo -v -L "$CORE_DIR/dinothawr_libretro.so" "$DINO_DIR/dinothawr.game" # | tee "$ROM_DIR/dinothawr.log"
