#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "***** gameswitcher.sh: helperFunctions imported" -v

BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
FLAG_PATH="/mnt/SDCARD/spruce/flags"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
LIST_FILE="$SETTINGS_PATH/gs_list"
IMAGES_FILE="$FLAG_PATH/gs_images"
GAMENAMES_FILE="$FLAG_PATH/gs_names"
TEMP_FILE="$FLAG_PATH/gs_list_temp"
OPTIONS_FILE="$FLAG_PATH/gs_options"
log_message "***** gameswitcher.sh: gs lock, list, images, names, options and temp list paths defined." -v

INFO_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"
DEFAULT_IMG="/mnt/SDCARD/Themes/SPRUCE/icons/ports.png"

# remove flag for game switcher
flag_remove "gs"
log_message "***** gameswitcher.sh: Removed game switcher flag file" -v

# exit if no game in list file
if [ ! -f "$LIST_FILE" ] ; then
    log_message "***** gameswitcher.sh: no games in the game switcher list! Exiting game switcher!" -v
    exit 0
fi

# prepare files for switcher program
rm -f "$IMAGES_FILE"
rm -f "$GAMENAMES_FILE"
log_message "***** gameswitcher.sh: cleared out previous images and game names files" -v
while read -r CMD; do
    # get and store game name to file
    GAME_PATH=$(echo $CMD | cut -d\" -f4)
    GAME_NAME="${GAME_PATH##*/}"
    SHORT_NAME="${GAME_NAME%.*}"
    log_message "***** gameswitcher.sh: CMD: $CMD" -v

    echo "$SHORT_NAME" >> "$GAMENAMES_FILE"
    log_message "***** gameswitcher.sh: Added $SHORT_NAME to $GAMENAMES_FILE" -v

    # try get box art file path
    BOX_ART_PATH="$(dirname "$GAME_PATH")/Imgs/$(basename "$GAME_PATH" | sed 's/\.[^.]*$/.png/')"
    log_message "***** gameswitcher.sh: BOX_ART_PATH: $BOX_ART_PATH" -v

    # try get screenshot file path only if boxart flag does not exist
    if [ ! -f "$FLAG_PATH/gs.boxart" ] ; then
        LAUNCH="$(echo "$CMD" | awk '{print $1}' | tr -d '"')"
        EMU_NAME="$(echo "$GAME_PATH" | cut -d'/' -f5)"
        EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
        DEF_DIR="/mnt/SDCARD/Emu/.emu_setup/defaults"
        OPT_DIR="/mnt/SDCARD/Emu/.emu_setup/options"
        OVR_DIR="/mnt/SDCARD/Emu/.emu_setup/overrides"
        DEF_FILE="$DEF_DIR/${EMU_NAME}.opt"
        OPT_FILE="$OPT_DIR/${EMU_NAME}.opt"
        OVR_FILE="$OVR_DIR/$EMU_NAME/$GAME.opt"
            . "$DEF_FILE"
            . "$OPT_FILE"
        if [ -f "$OVR_FILE" ]; then
            . "$OVR_FILE"
        fi
        core_info="$INFO_DIR/${CORE}_libretro.info"
        core_name="$(awk -F' = ' '/corename/ {print $2}' "$core_info")"
        core_name="$(echo ${core_name} | tr -d '"')"
        state_dir="/mnt/SDCARD/Saves/states/$core_name"
        SCREENSHOT_PATH="${state_dir}/${SHORT_NAME}.state.auto.png"
        log_message "***** gameswitcher.sh: SCREENSHOT_PATH: $SCREENSHOT_PATH" -v
    fi

    # store screenshot / box art / default image to file
    if [ -f "$SCREENSHOT_PATH" ] ; then
        echo "$SCREENSHOT_PATH" >> "$IMAGES_FILE"
        log_message "***** gameswitcher.sh: using screenshot for $GAME_NAME" -v
    elif [ -f "$BOX_ART_PATH" ]; then
        echo "$BOX_ART_PATH" >> "$IMAGES_FILE"
        log_message "***** gameswitcher.sh: using boxart for $GAME_NAME" -v
    else
        echo "$DEFAULT_IMG" >> "$IMAGES_FILE"
        log_message "***** gameswitcher.sh: using default image for $GAME_NAME" -v
    fi
done <$LIST_FILE

# launch the switcher program
# Usage: switcher image_list title_list [-s speed] [-b on|off] [-m on|off] [-t on|off] [-ts speed] [-n on|off] [-d command]
# -s: scrolling speed in frames (default is 20), larger value means slower.
# -b: swap left/right buttons for image scrolling (default is off).
# -m: display title in multiple lines (default is off).
# -t: display title at start (default is on).
# -ts: title scrolling speed in pixel per frame (default is 4).
# -n: display item index (default is on).
# -d: enable item deletion (default is on).
# -dc: additional deletion command runs when an item is deleted (default is none).
#      Use INDEX in command to take the selected index as input. e.g. "echo INDEX"
# -h,--help show this help message.
# return value: the 1-based index of the selected image
while : ; do
    # set options 
    OPTIONS="-s 10"
    if [ -f $OPTIONS_FILE ] ; then
        OPTIONS=$(cat $OPTIONS_FILE)
    fi

    # run switcher
    log_message "***** gameswitcher.sh: launching actual switcher executable" -v
    cd $BIN_PATH
    ./switcher "$IMAGES_FILE" "$GAMENAMES_FILE" $OPTIONS \
    -dc "sed -i 'INDEXs/.*/removed/' $LIST_FILE"

    # get return value
    RETURN_INDEX=$?

    # skip all removed items
    grep -Fxv "removed" "$LIST_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$LIST_FILE"

    # show setting page if return value is 255, otherwise exit while loop
    if [ $RETURN_INDEX -eq 255 ]; then
        # start setting program
        cd $BIN_PATH
        ./easyConfig $SETTINGS_PATH/spruce_config 
    else
        break
    fi
done

# launch game with return index
if [ $RETURN_INDEX -gt 0 ]; then
    # get command that launches the game
    CMD=$(tail -n+$RETURN_INDEX "$LIST_FILE" | head -1)

    # move the selected game to the end of the list file & skip all removed items
    # 1. get all commands except the selected game or removed lines
    grep -Fxv "$CMD" "$LIST_FILE" | grep -Fxv "removed" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$LIST_FILE"
    # 2. append the command for current game to the end of game list file 
    echo "$CMD" >> "$LIST_FILE"

    # write command to file which will be run by principle.sh
    log_message "attempting $CMD" -v
    echo $CMD > /tmp/cmd_to_run.sh
    sync
fi
