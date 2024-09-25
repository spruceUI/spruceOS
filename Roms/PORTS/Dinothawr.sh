#!/bin/sh

ROM_DIR="$(dirname "$0")"
RA_DIR="/mnt/SDCARD/RetroArch"
DINO_DIR="$RA_DIR/.retroarch/downloads/dinothawr"
CORE_DIR="$RA_DIR/.retroarch/cores"

cd "$RA_DIR"

mv "./retroarch.cfg" "./retroarch.cfg.bak"
cp "./hotkeyprofile/retroarch.cfg" "./retroarch.cfg"

./retroarch -v -L "$CORE_DIR/dinothawr_libretro.so" "$DINO_DIR/dinothawr.game"

rm "./retroarch.cfg"
mv "./retroarch.cfg.bak" "./retroarch.cfg"
