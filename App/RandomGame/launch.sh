#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ICON="/mnt/SDCARD/spruce/imgs/random.png"
display --icon "$ICON" -t "Selecting random game - please wait a moment"

GAME="$("$(get_python_path)" "$(dirname "$0")/pick_game.py")"
if [ -z "$GAME" ]; then
    display --icon "$ICON" -t "No eligible games found. Add some games first!" -d 3
    exit 1
fi

SYSTEM="$(basename "$(dirname "$GAME")")"
BOX_ART="$(dirname "$GAME")/Imgs/$(basename "$GAME" | sed 's/\.[^.]*$/.png/')"
if [ -f "$BOX_ART" ]; then
    display -i "$BOX_ART" -d 2
    kill $(jobs -p)
fi

# standard_launch.sh takes EMU_NAME from its own path, so it has to be reached
# through Emu/<system>/. button_actions.sh greps that string back out of
# /tmp/cmd_to_run.sh for the game switcher.
LAUNCH_SCRIPT="/mnt/SDCARD/Emu/${SYSTEM}/../../spruce/scripts/emu/standard_launch.sh"
echo "\"$LAUNCH_SCRIPT\" \"$GAME\"" > /tmp/cmd_to_run.sh
"$LAUNCH_SCRIPT" "$GAME"

auto_regen_tmp_update
