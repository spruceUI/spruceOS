#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LIVE_RA_CFG="$(platform_path "/mnt/SDCARD/Saves/ra-configs/retroarch-%s.cfg")"
BAK_RA_CFG="$(platform_path "/mnt/SDCARD/RetroArch/platform/retroarch-%s.cfg.bak")"

if [ ! -f "$LIVE_RA_CFG" ] && [ -f "$BAK_RA_CFG" ]; then
    mkdir -p /mnt/SDCARD/Saves/ra-configs
    cp "$BAK_RA_CFG" "$LIVE_RA_CFG" && log_message "$LIVE_RA_CFG seeded from .bak file."
fi

set_default_ra_hotkeys

log_message "RetroArch hotkeys have been reset to defaults."
