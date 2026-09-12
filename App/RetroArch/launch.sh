#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Ensure we have all needed EMU setup
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh

prepare_ra_config 2>/dev/null
cd "$RA_DIR/"
RA_PARAMS="-v --config ${PLATFORM_CFG}"

# Same 32-bit overlay a game launch gets (a no-op for this 64-bit build, whose
# platform cfg carries its own drivers and binds).
apply_baseos_ra_overlay

HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS


auto_regen_tmp_update
