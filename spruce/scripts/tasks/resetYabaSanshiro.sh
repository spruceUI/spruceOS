#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Standalone only: its keymap sits in Emu/SATURN/.yabasanshiro, which spruceBackup carries across updates, so this
# release's default ships in Emu/SATURN/default_configs. backup.bin (battery RAM), RetroArch's YabaSanshiro files and
# the menu picks are never touched; each board's pad seed is applied again at launch.
DEF=/mnt/SDCARD/Emu/SATURN/default_configs

restore() {  # restore <default> <live>
    [ -f "$1" ] || { log_message "Reset YabaSanshiro config: $1 does not exist, $2 not restored"; return 1; }
    mkdir -p "${2%/*}"
    [ -f "$1" ] && cp -f "$1" "$2"
}

log_message "Resetting YabaSanshiro config to default."
restore "$DEF/yabasanshiro/keymapv2.json" /mnt/SDCARD/Emu/SATURN/.yabasanshiro/keymapv2.json
