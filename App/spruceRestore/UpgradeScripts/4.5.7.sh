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
move_setting "Emulator Settings" "In-Game Menu Settings" raInGameMenu
move_setting "Emulator Settings" "In-Game Menu Settings" raIgmColorway

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

# Recover DraStic saves and states buried by the old architecture-folder moves.
# Keep colliding files in a recovered folder rather than overwriting either copy.
NDS_EMU_DIR=/mnt/SDCARD/Emu/NDS
move_drastic_saves() {
    _from="$NDS_EMU_DIR/$1"
    _to="$NDS_EMU_DIR/$2"
    [ -d "$_from" ] || return 0
    if [ ! -e "$_to" ]; then
        if mv "$_from" "$_to"; then
            return 0
        fi
        log_message "4.5.7: failed to move DraStic $1 to $2"
        return 1
    fi
    for _f in "$_from"/* "$_from"/.[!.]*; do
        [ -e "$_f" ] || continue
        _name="${_f##*/}"
        if [ "$_name" = ".gitkeep" ]; then
            if ! rm -f "$_f"; then
                log_message "4.5.7: failed to remove DraStic placeholder $1/$_name"
                return 1
            fi
        elif [ ! -e "$_to/$_name" ]; then
            if ! mv "$_f" "$_to/"; then
                log_message "4.5.7: failed to recover DraStic $1/$_name into $2"
                return 1
            fi
        else
            log_message "4.5.7: DraStic $1/$_name conflicts with $2/$_name; keeping it apart"
        fi
    done
    rmdir "$_from" 2>/dev/null || true
}

if [ -d "$NDS_EMU_DIR" ]; then
    while :; do
        _found_nested=0
        for _dir in backup backup-32 backup-64; do
            for _nested in backup backup-32 backup-64; do
                [ -d "$NDS_EMU_DIR/$_dir/$_nested" ] || continue
                _found_nested=1
                if ! move_drastic_saves "$_dir/$_nested" "$_dir"; then
                    exit 1
                fi
                if [ -d "$NDS_EMU_DIR/$_dir/$_nested" ]; then
                    _recovered="$NDS_EMU_DIR/$_dir/recovered-$_nested"
                    _suffix=1
                    while [ -e "$_recovered" ]; do
                        _recovered="$NDS_EMU_DIR/$_dir/recovered-$_nested.$_suffix"
                        _suffix=$((_suffix + 1))
                    done
                    if mv "$NDS_EMU_DIR/$_dir/$_nested" "$_recovered"; then
                        log_message "4.5.7: kept conflicting DraStic files in ${_recovered##*/}"
                    else
                        log_message "4.5.7: failed to preserve conflicting DraStic files in $_dir/$_nested"
                        exit 1
                    fi
                fi
            done
        done
        [ "$_found_nested" -eq 1 ] || break
    done
fi

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

# Existing DSperate profiles predate the GBA paths and analog cheat database.
# Add only missing keys so user-defined paths remain unchanged; per-game INIs
# under the games/ subdirectory are intentionally left alone.
add_dsperate_path() {
    _ini=$1
    _key=$2
    _value=$3
    grep -q "^[[:space:]]*${_key}[[:space:]]*=" "$_ini" && return 0
    if ! grep -q '^[[:space:]]*\[paths\][[:space:]]*$' "$_ini"; then
        log_message "4.5.7: no [paths] section in $_ini; cannot add $_key"
        return 1
    fi
    if sed -i "/^[[:space:]]*\\[paths\\][[:space:]]*$/a ${_key} = ${_value}" "$_ini"; then
        log_message "4.5.7: added $_key to $_ini"
    else
        log_message "4.5.7: failed to add $_key to $_ini"
        return 1
    fi
}

for _ini in /mnt/SDCARD/Saves/dsperate/*.ini; do
    [ -f "$_ini" ] || continue
    add_dsperate_path "$_ini" gba_games /mnt/SDCARD/Roms/GBA || exit 1
    add_dsperate_path "$_ini" gba_saves /mnt/SDCARD/Saves/saves/armGBA || exit 1
    add_dsperate_path "$_ini" analog_cheats /mnt/SDCARD/Emu/NDS/cheats/usrcheat-analog.dat || exit 1
done

# Touch now reaches the RetroArch menu on the XU20 and Zero40: pointer on, mouse off.
# Once per card, as nightlies rerun this script and the user may turn the mouse back on.
_ra_touch_done=/mnt/SDCARD/Saves/spruce/.ra-menu-touch-set
if [ ! -f "$_ra_touch_done" ]; then
    for _cfg in /mnt/SDCARD/Saves/ra-configs/retroarch-XU20.cfg /mnt/SDCARD/Saves/ra-configs/retroarch-Zero40.cfg /mnt/SDCARD/Saves/ra-configs/retroarch-RG353M.cfg; do
        [ -f "$_cfg" ] || continue
        sed -i -e 's/^menu_pointer_enable = "false"$/menu_pointer_enable = "true"/' \
            -e 's/^menu_mouse_enable = "true"$/menu_mouse_enable = "false"/' "$_cfg"
        log_message "4.5.7: RetroArch menu touch on in $_cfg"
    done
    touch "$_ra_touch_done"
fi


# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
