#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Ensure we have all needed EMU setup
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh


prepare_ra_config 2>/dev/null
cd $RA_DIR/
HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v
backup_ra_config 2>/dev/null

auto_regen_tmp_update