#!/bin/sh

. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"

if [ "$1" = "on" ]; then
    sed -i 's/^savestate_auto_save = .*/savestate_auto_save = "true"/' "$RETROARCH_CFG"
    sed -i 's/^savestate_auto_load = .*/savestate_auto_load = "true"/' "$RETROARCH_CFG"
else
    sed -i 's/^savestate_auto_save = .*/savestate_auto_save = "false"/' "$RETROARCH_CFG"
    sed -i 's/^savestate_auto_load = .*/savestate_auto_load = "false"/' "$RETROARCH_CFG"
fi
