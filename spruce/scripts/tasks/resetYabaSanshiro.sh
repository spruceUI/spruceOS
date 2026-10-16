#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Saturn's live settings sit in trees spruceBackup carries across updates (Emu/SATURN/.yabasanshiro and
# RetroArch/.retroarch/config), so this release's defaults ship in Emu/SATURN/default_configs, which every update
# replaces. backup.bin (the Saturn's battery RAM) is never touched; each board's pad seed is applied again at launch.
DEF=/mnt/SDCARD/Emu/SATURN/default_configs
CFG=/mnt/SDCARD/Emu/SATURN/config.json

restore() {  # restore <default> <live>
    [ -f "$1" ] || { log_message "Reset YabaSanshiro config: $1 does not exist, $2 not restored"; return 1; }
    mkdir -p "${2%/*}"
    [ -f "$1" ] && cp -f "$1" "$2"
}

log_message "Resetting YabaSanshiro config to default."
restore "$DEF/yabasanshiro/keymapv2.json" /mnt/SDCARD/Emu/SATURN/.yabasanshiro/keymapv2.json
restore "$DEF/retroarch/YabaSanshiro/YabaSanshiro.opt" /mnt/SDCARD/RetroArch/.retroarch/config/YabaSanshiro/YabaSanshiro.opt
restore "$DEF/retroarch/YabaSanshiro/YabaSanshiro.cfg" /mnt/SDCARD/RetroArch/.retroarch/config/YabaSanshiro/YabaSanshiro.cfg

# Menu picks: a shipped pick goes back only where its option still offers it; per-game overrides stay.
if [ -f "$DEF/picks.json" ] && [ -f "$CFG" ]; then
    jq --slurpfile p "$DEF/picks.json" '
        reduce ($p[0].SATURN | to_entries[]) as $e (.;
            if ([.menuOptions[$e.key].options[]? | if type == "object" then .label else . end] | any(. == $e.value))
            then .menuOptions[$e.key].selected = $e.value else . end)' "$CFG" > "$CFG.tmp" \
        && [ -s "$CFG.tmp" ] && mv -f "$CFG.tmp" "$CFG" \
        || { rm -f "$CFG.tmp"; log_message "Reset YabaSanshiro config: Saturn menu picks not reset"; }
else
    log_message "Reset YabaSanshiro config: $DEF/picks.json or $CFG missing, menu picks not reset"
fi
