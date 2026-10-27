#!/bin/sh

TARGET_VERSION="4.5.7"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# Settings that moved to another category or were renamed: merge_configs.py
# matches by path, so move them in the backup or the saved choice resets.
# move_setting OLD_CATEGORY NEW_CATEGORY KEY [NEW_KEY]
move_setting() {
    _old=".menuOptions.\"$1\".\"$3\""
    _new=".menuOptions.\"$2\".\"${4:-$3}\""
    for _cfg in /mnt/SDCARD/Saves/spruce/spruce-config.json /mnt/SDCARD/Saves/spruce/backups/spruce-config.json; do
        [ -f "$_cfg" ] || continue
        [ "$(jq -r "$_old.selected // \"\"" "$_cfg")" != "" ] || continue
        jq "$_new = $_old | del($_old)" "$_cfg" > "$_cfg.tmp" && mv "$_cfg.tmp" "$_cfg"
        log_message "Moved $1 $3 to $2 ${4:-$3} in $_cfg"
    done
}

move_setting "Battery Settings" "System Settings" ledMode
move_setting "Game Switcher Settings" "Button Settings" menuHoldTime
move_setting "Game Switcher Settings" "Button Settings" menuShouldVibrate
move_setting "Emulator Settings" "Button Settings" tapHomeAction tapMenuAction
move_setting "Emulator Settings" "Button Settings" holdHomeAction holdMenuAction

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

# Overlay packs moved from overlay/ (640x480) and overlay/Brick (1024x768) into a folder per
# resolution. Move each pack the old archives unpacked, or drop it where an install already put
# the new copy, then point RetroArch configs at the new paths.
OVERLAY_DIR=/mnt/SDCARD/RetroArch/.retroarch/overlay
move_overlay_pack() {
    [ -d "$OVERLAY_DIR/$1" ] || return 0
    if [ -d "$OVERLAY_DIR/$2" ]; then
        rm -rf "$OVERLAY_DIR/$1"
        log_message "Removed old overlay pack $1, $2 is already there"
    else
        mkdir -p "$(dirname "$OVERLAY_DIR/$2")" && mv "$OVERLAY_DIR/$1" "$OVERLAY_DIR/$2"
        log_message "Moved overlay pack $1 to $2"
    fi
}

for _pack in "Custom Blue Power Button" "Custom Purple Power Button" drkhrse GBA Jeltron Onion-Spruce Perfect; do
    move_overlay_pack "$_pack" "640x480/$_pack"
done
for _pack in "Jeltron-Brick Overlays v2" "Skywalker Overlays"; do
    move_overlay_pack "Brick/$_pack" "1024x768/$_pack"
done
rmdir "$OVERLAY_DIR/Brick" 2>/dev/null

# Jeltron's copies of two Onion-Spruce CRT overlays are gone; configs use Onion-Spruce's.
rm -f "$OVERLAY_DIR/640x480/Jeltron/CRT_FrameOnly".cfg "$OVERLAY_DIR/640x480/Jeltron/CRT_FrameOnly".png \
    "$OVERLAY_DIR/640x480/Jeltron/CRT_Scanlines_Colored".cfg "$OVERLAY_DIR/640x480/Jeltron/CRT_Scanlines_Colored".png

find /mnt/SDCARD/RetroArch -name '*.cfg' ! -path "$OVERLAY_DIR/*" 2>/dev/null | while read -r _cfg; do
    grep -q -E 'overlay/((640x480/)?Jeltron/CRT_|Custom (Blue|Purple) Power Button/|drkhrse/|GBA/|Jeltron/|Onion-Spruce/|Perfect/|Brick/)' "$_cfg" || continue
    sed -i -E \
        -e 's#overlay/(640x480/)?Jeltron/CRT_FrameOnly\.cfg#overlay/640x480/Onion-Spruce/4-3/Frames/CRT_FrameOnly.cfg#g' \
        -e 's#overlay/(640x480/)?Jeltron/CRT_Scanlines_Colored\.cfg#overlay/640x480/Onion-Spruce/4-3/CRT/CRT_Scanlines_Colored.cfg#g' \
        -e 's#overlay/(Custom Blue Power Button|Custom Purple Power Button|drkhrse|GBA|Jeltron|Onion-Spruce|Perfect)/#overlay/640x480/\1/#g' \
        -e 's#overlay/Brick/#overlay/1024x768/#g' "$_cfg"
    log_message "Pointed overlays in $_cfg at their new folders"
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
