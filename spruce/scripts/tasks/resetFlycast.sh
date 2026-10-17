#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# An update restores the player's Emu/DC/config and RetroArch config trees (spruceBackup), so this release's Flycast
# defaults live in Emu/DC/default_configs, outside both; this task is how they reach an updated card.
DEF="/mnt/SDCARD/Emu/DC/default_configs"
LIVE_CFG="/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg"
DEFAULT_CFG="$DEF/flycast/emu.cfg"
LIVE_MAP="/mnt/SDCARD/Emu/DC/config/flycast/mappings/SDL_Xbox 360 Controller.cfg"
DEFAULT_MAP="$DEF/flycast/mappings/SDL_Xbox 360 Controller.cfg"
RA_CONFIG="/mnt/SDCARD/RetroArch/.retroarch/config"

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

# RetroArch core files: default_configs/retroarch mirrors RetroArch/.retroarch/config (the layout all series share)
[ -d "$DEF/retroarch" ] && (cd "$DEF/retroarch" && find . -type f) | while IFS= read -r f; do
    DEFAULT_FILE="$DEF/retroarch/$f"
    LIVE_FILE="$RA_CONFIG/$f"
    mkdir -p "${LIVE_FILE%/*}"
    [ -e "$DEFAULT_FILE" ] && cp -f "$DEFAULT_FILE" "$LIVE_FILE"
done

# Menu picks: each shipped "selected" value goes back where its option still offers it; per-game overrides stay.
for emu in DC NAOMI ATOMISWAVE; do
    json="/mnt/SDCARD/Emu/$emu/config.json"
    [ -f "$json" ] && [ -f "$DEF/picks.json" ] || continue
    jq --argjson p "$(jq -c --arg e "$emu" '.[$e] // {}' "$DEF/picks.json")" '
        reduce ($p | to_entries[]) as $kv (.;
            if .menuOptions[$kv.key] == null then .
            elif (.menuOptions[$kv.key].options | type) == "array"
                 and (.menuOptions[$kv.key].options | index($kv.value)) == null then .
            else .menuOptions[$kv.key].selected = $kv.value end)' "$json" > "$json.tmp" \
        && mv "$json.tmp" "$json" || { rm -f "$json.tmp"; log_message "Reset Flycast config: picks for $emu not restored"; }
done
