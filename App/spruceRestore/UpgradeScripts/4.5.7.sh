#!/bin/sh

TARGET_VERSION="4.5.7"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# Settings that moved to another category: merge_configs.py matches by path, so
# move them in the backup or the saved choice resets to the default.
# move_setting OLD_CATEGORY NEW_CATEGORY KEY
move_setting() {
    _old=".menuOptions.\"$1\".\"$3\""
    _new=".menuOptions.\"$2\".\"$3\""
    for _cfg in /mnt/SDCARD/Saves/spruce/spruce-config.json /mnt/SDCARD/Saves/spruce/backups/spruce-config.json; do
        [ -f "$_cfg" ] || continue
        [ "$(jq -r "$_old.selected // \"\"" "$_cfg")" != "" ] || continue
        jq "$_new = $_old | del($_old)" "$_cfg" > "$_cfg.tmp" && mv "$_cfg.tmp" "$_cfg"
        log_message "Moved $3 from $1 to $2 in $_cfg"
    done
}

move_setting "Battery Settings" "System Settings" ledMode
move_setting "Game Switcher Settings" "Button Settings" menuHoldTime
move_setting "Game Switcher Settings" "Button Settings" menuShouldVibrate

# Menu hold time lost its 0 and 4 options: keep the nearest choice.
_hold='.menuOptions."Button Settings".menuHoldTime.selected'
for _cfg in /mnt/SDCARD/Saves/spruce/spruce-config.json /mnt/SDCARD/Saves/spruce/backups/spruce-config.json; do
    [ -f "$_cfg" ] || continue
    case "$(jq -r "$_hold // \"\"" "$_cfg")" in
        0) _to="0.2" ;;
        4) _to="3" ;;
        *) continue ;;
    esac
    jq "$_hold = \"$_to\"" "$_cfg" > "$_cfg.tmp" && mv "$_cfg.tmp" "$_cfg"
    log_message "Menu hold time set to $_to in $_cfg"
done


# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
