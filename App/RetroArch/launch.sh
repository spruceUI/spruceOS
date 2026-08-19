#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Ensure we have all needed EMU setup
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh

prepare_ra_config 2>/dev/null
cd "$RA_DIR/"
RA_PARAMS="-v --config ${PLATFORM_CFG}"

# Same BaseOS overlay and joypad autoconfig a game launch gets. This build got
# away without it - the universal cfg already names the sdl2 joypad driver and a
# previous game launch leaves a matching autoconfig on disk - but it was missing
# video_context_driver = fbdev_mali, so it worked by luck rather than by design.
apply_baseos_ra_overlay

HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS


auto_regen_tmp_update
