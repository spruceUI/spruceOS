#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Ensure we have all needed EMU setup
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh


prepare_ra_config 2>/dev/null
setup_for_retroarch_and_get_bin_location
cd "$RA_DIR/"

RA_PARAMS="-v"
case "$PLATFORM" in
    "Pixel2"|"Flip"|"SmartPro"|"SmartProS"|"Brick"|"A30"|"MiyooMini"|"Anbernic"*)
        CURRENT_CFG=$(get_ra_cfg_location)
        RA_PARAMS="${RA_PARAMS} --config ${CURRENT_CFG}"
        ;;
esac

HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS

backup_ra_config 2>/dev/null

auto_regen_tmp_update
