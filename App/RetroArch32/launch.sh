#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Ensure we have all needed EMU setup
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh

export RA_BIN="ra32.universal"
setup_for_retroarch

prepare_ra_config 2>/dev/null

# Ensure 64-bit cores directory is restored on any exit (normal, SIGTERM, crash)
trap '
    TMP_CFG="$(mktemp)"
    sed "s|^libretro_directory.*|libretro_directory = \"./.retroarch/cores64\"|" "$PLATFORM_CFG" > "$TMP_CFG"
    mv "$TMP_CFG" "$PLATFORM_CFG"
' EXIT

# Point RA at 32-bit cores directory for in-menu core browsing
TMP_CFG="$(mktemp)"
sed 's|^libretro_directory.*|libretro_directory = "./.retroarch/cores"|' "$PLATFORM_CFG" > "$TMP_CFG"
mv "$TMP_CFG" "$PLATFORM_CFG"

cd "$RA_DIR/"
RA_PARAMS="-v --config ${PLATFORM_CFG}"

# Same BaseOS overlay and joypad autoconfig a game launch gets. Without it this
# app ran on the universal cfg's sdl2 joypad driver, which sees no pad on
# BaseOS, so the frontend came up with dead controls.
apply_baseos_ra_overlay

HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS

auto_regen_tmp_update
