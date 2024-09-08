#!/bin/sh

ROM_DIR="$(dirname "$0")"
RA_DIR="/mnt/SDCARD/RetroArch"
CORE_DIR="$RA_DIR/.retroarch/cores"

cd "$RA_DIR"

./ra32.miyoo -v -L "$CORE_DIR/gong_libretro.so" # | tee "$ROM_DIR/gong.log"
