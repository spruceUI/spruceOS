#!/bin/sh

ROM_DIR="$(dirname "$0")"
RA_DIR="/mnt/SDCARD/RetroArch"
CORE_DIR="$RA_DIR/.retroarch/cores"

cd "$RA_DIR"
./retroarch -v -L "$CORE_DIR/2048_libretro.so"