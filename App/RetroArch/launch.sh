#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Ensure we have all needed EMU setup
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh


prepare_ra_config 2>/dev/null
cd $RA_DIR/

RA_PARAMS="-v"
if [ "$PLATFORM" = "Pixel2" ] || [ "$PLATFORM" = "Flip" ]; then
    CURRENT_CFG=$(get_ra_cfg_location)
    RA_PARAMS="${RA_PARAMS} --config ${CURRENT_CFG}"
fi

HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS

backup_ra_config 2>/dev/null

auto_regen_tmp_update
