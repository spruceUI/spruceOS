#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ICON="/mnt/SDCARD/spruce/imgs/random.png"
start_pyui_message_writer
display_image_and_text "$ICON" 35 25 "Selecting random game - please wait a moment" 75

GAME="$("$(get_python_path)" "$(dirname "$0")/pick_game.py")"
if [ -z "$GAME" ]; then
    display_image_and_text "$ICON" 35 25 "No eligible games found. Add some games first!" 75
    sleep 3
    stop_pyui_message_writer
    exit 1
fi

SYSTEM="${GAME#/mnt/SDCARD/Roms/}"
SYSTEM="${SYSTEM%%/*}"
ROM_PATH="${GAME#/mnt/SDCARD/Roms/$SYSTEM/}"
ROM_PATH="${ROM_PATH%.*}"
BOX_ART="/mnt/SDCARD/Roms/$SYSTEM/Imgs/$ROM_PATH.png"
[ -f "$BOX_ART" ] || BOX_ART="/mnt/SDCARD/Roms/$SYSTEM/Imgs/${ROM_PATH##*/}.png"
if [ -f "$BOX_ART" ]; then
    log_message "Display image $BOX_ART"
    display_message "$(printf '{"cmd":"RENDER_IMAGE","args":["%s"]}' "$(json_escape "$BOX_ART")")"
    sleep 3
fi
stop_pyui_message_writer

# standard_launch.sh takes EMU_NAME from its own path, so it has to be reached
# through Emu/<system>/. button_actions.sh greps that string back out of
# /tmp/cmd_to_run.sh for the game switcher.
LAUNCH_SCRIPT="/mnt/SDCARD/Emu/${SYSTEM}/../../spruce/scripts/emu/standard_launch.sh"
echo "\"$LAUNCH_SCRIPT\" \"$GAME\"" > /tmp/cmd_to_run.sh
"$LAUNCH_SCRIPT" "$GAME"

auto_regen_tmp_update
