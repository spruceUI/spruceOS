#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Standalone only: an update restores the player's Emu/DC/config (spruceBackup), so this release's defaults live in
# Emu/DC/default_configs, outside it. RetroArch's Flycast files and the DC/NAOMI/Atomiswave menu picks are left alone.
DEF="/mnt/SDCARD/Emu/DC/default_configs"
LIVE_CFG="/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg"
DEFAULT_CFG="$DEF/flycast/emu.cfg"
LIVE_MAP="/mnt/SDCARD/Emu/DC/config/flycast/mappings/SDL_Xbox 360 Controller.cfg"
DEFAULT_MAP="$DEF/flycast/mappings/SDL_Xbox 360 Controller.cfg"

log_message "Resetting Flycast config to default."
[ -e "$DEFAULT_CFG" ] && cp -f "$DEFAULT_CFG" "$LIVE_CFG"
[ -e "$DEFAULT_CFG" ] || log_message "Reset Flycast config: $DEFAULT_CFG does not exist, nothing restored"
[ -e "$DEFAULT_MAP" ] && cp -f "$DEFAULT_MAP" "$LIVE_MAP"
[ -e "$DEFAULT_MAP" ] || log_message "Reset Flycast config: $DEFAULT_MAP does not exist, mapping not restored"
# NAOMI/Atomiswave use the _arcade file when it exists, else a clone of the Dreamcast one
LIVE_ARCADE_MAP="${LIVE_MAP%.cfg}_arcade.cfg"
DEFAULT_ARCADE_MAP="${DEFAULT_MAP%.cfg}_arcade.cfg"
[ -e "$DEFAULT_ARCADE_MAP" ] && cp -f "$DEFAULT_ARCADE_MAP" "$LIVE_ARCADE_MAP"
[ -e "$DEFAULT_ARCADE_MAP" ] || log_message "Reset Flycast config: $DEFAULT_ARCADE_MAP does not exist, arcade mapping not restored"

# The board's pad map table (FLYCAST_PAD_MAP, from its platform cfg; UNVERIFIED generated maps, DC controls audit)
if [ -n "$FLYCAST_PAD_MAP" ]; then
    for DEFAULT_PAD in "$DEF/flycast/pads/$FLYCAST_PAD_MAP"/SDL_*.cfg; do
        LIVE_PAD="${LIVE_MAP%/*}/${DEFAULT_PAD##*/}"
        [ -e "$DEFAULT_PAD" ] && cp -f "$DEFAULT_PAD" "$LIVE_PAD"
        [ -e "$DEFAULT_PAD" ] || log_message "Reset Flycast config: $DEF/flycast/pads/$FLYCAST_PAD_MAP does not exist, pad map not restored"
    done
fi
