#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/random.png"

display --icon "$IMAGE_PATH" -t "Selecting random game - please wait a moment"
PREV_SELECTION_FILE="/mnt/SDCARD/App/RandomGame/prev_selection.txt"
PREV5_FILE="/mnt/SDCARD/App/RandomGame/5_previous.txt"

get_rand_folder() {
    local folder="$1"

    # count all files (except xml files) in all sub-folders
    SIZE=$(find "$folder" -mindepth 2 -maxdepth 2 -type f ! -name "*.xml" | wc -l)

    # generate random index (0 - SIZE)
    SEED=$(date +%N)
    RINDEX=$(awk -v max=$SIZE -v seed=$SEED 'BEGIN{srand(seed); print int(rand()*(max))}')

    # find the selected sub-folder
    for SUBFOLDER in "$folder"/*/; do

        # count all files in sub-folder
        SUBSIZE=$(find "$SUBFOLDER" -maxdepth 1 -type f ! -name "*.xml" | wc -l)

        # select sub folder if the randon index is in range  
        if [ $RINDEX -lt $SUBSIZE ]; then
        #if [ $RINDEX -eq 0 ]; then
            echo -n "$SUBFOLDER"
            return
        fi

        # adjust random index
        RINDEX=$(expr $RINDEX - $SUBSIZE)
    done
}

get_rand_file() {
    local folder="$1"
    sys_name=$(basename "$folder")
    extensions="$(jq -r '.extlist' "/mnt/SDCARD/Emu/$sys_name/config.json" | awk '{gsub(/\|/, " "); print $0}')"
    OIFS="$IFS"
    IFS=$'\n'
    ALL_FILES=$(ls -d -1 "$folder"* | grep -E "\.($(echo "$extensions" | sed -e "s/ /\|/g"))$" | grep -Fxvf "$PREV5_FILE")
    SIZE=$(echo "$ALL_FILES" | wc -l)
    match=""
    if [ $SIZE -gt 0 ]; then
        SEED=$(date +%N)
        RINDEX=$(awk -v max=$SIZE -v seed=$SEED 'BEGIN{srand(seed); print int(rand()*(max))}')
        for file in $ALL_FILES; do
            if [ $RINDEX -eq 0 ]; then
                match="${file}"
                break
            fi
            RINDEX=$(expr $RINDEX - 1)
        done
    fi
    IFS="$OIFS"
    [ -n "$match" ] && echo -n "$match"
}

ROM_DIR="/mnt/SDCARD/Roms"
EMU_DIR="/mnt/SDCARD/Emu"

if [ ! -d "$ROM_DIR" ] || [ ! -d "$EMU_DIR" ]; then
    exit 1
fi

NOTOK=1
MAX_ATTEMPTS=30
attempt_count=0
while [ "$NOTOK" -eq 1 ]; do
    NOTOK=0
    attempt_count=$((attempt_count + 1))
    if [ "$attempt_count" -gt "$MAX_ATTEMPTS" ]; then
        display --icon "$IMAGE_PATH" -t "No eligible games found. Add some games first!" -d 3
        exit 1
    fi
    # TODO: this _will_ select an empty folder, probably shouldn't
    SELECTED_FOLDER=$(get_rand_folder "$ROM_DIR")
    SELECTED_GAME=$(get_rand_file "$SELECTED_FOLDER")
    echo "${SELECTED_FOLDER} ${SELECTED_GAME}"
    if [ -z "$SELECTED_GAME" ]; then
        NOTOK=1
        continue
    fi
    echo "$SELECTED_GAME" >> "$PREV_SELECTION_FILE"
    tail -n 5 "$PREV_SELECTION_FILE" > "$PREV5_FILE"
    FOLDER_NAME=$(basename "$SELECTED_FOLDER")
    EMU_FOLDER="$EMU_DIR/$FOLDER_NAME"
    if [ ! -d "$EMU_FOLDER" ]; then
        NOTOK=1
        continue
    fi
done

BOX_ART_PATH="$(dirname "$SELECTED_GAME")/Imgs/$(basename "$SELECTED_GAME" | sed 's/\.[^.]*$/.png/')"

if [ -f "$BOX_ART_PATH" ]; then
    display -i "$BOX_ART_PATH" -d 2
    kill $(jobs -p)
fi

# standard_launch.sh takes its identity from $0: it strips up to "/Emu/" and
# keeps the next path component as EMU_NAME. So it has to be invoked through
# Emu/<system>/, and the ../../ detour is load-bearing rather than redundant.
# Calling the canonical path directly leaves EMU_NAME empty and the game
# launches with no emulator. The same string goes to /tmp/cmd_to_run.sh, where
# button_actions.sh greps Emu/<system>/ back out for the game switcher.
LAUNCH_SCRIPT="/mnt/SDCARD/Emu/${FOLDER_NAME}/../../spruce/scripts/emu/standard_launch.sh"
echo "\"$LAUNCH_SCRIPT\" \"${SELECTED_GAME}\"" > /tmp/cmd_to_run.sh
"$LAUNCH_SCRIPT" "$SELECTED_GAME"

auto_regen_tmp_update
