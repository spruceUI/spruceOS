#!/bin/sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
NURSERY_DIR="/mnt/SDCARD/App/GameNursery"
JSON_DIR="/mnt/SDCARD/Saves/nursery"

create_config_from_json() {

    json_file="$1"
    grouping="$(basename "$(dirname "$json_file")")"


    display_name="$(jq -r '.display' "$json_file")"
    file="$(jq -r '.file' "$json_file")"
    system="$(jq -r '.system' "$json_file")"
    url="$(jq -r '.url' "$json_file")"
    description="$(jq -r '.description' "$json_file")"
    requires_files="$(jq -r '.requires_files' "$json_file")"
    version="$(jq -r '.version' "$json_file")"

    # add notice that additional files are needed
    if [ "$requires_files" = "true" ]; then
        description="$description Requires additional files."
    fi

    # add line for specific game
    echo "\"\" \"$display_name\" \"|\" \"run|off\" \"echo -n off\" \"\" \"\""

    # check whether game already installed
    if [ -f "/mnt/SDCARD/Roms/$system/$file" ]; then
        echo "@\"Already installed!\""
    else
        echo "@\"$description\""
    fi

}

# send signal USR2 to joystickinput to switch to KEYBOARD MODE
# this allows joystick to be used as DPAD in setting app
killall -q -USR2 joystickinput

# Initialize empty string for modes
MODES=""

# Easy to add more modes like this:
# if flag_check "some_other_mode"; then
#     MODES="$MODES -m other_mode"
# fi

# initialize nursery_config as empty text file
echo "" > "$NURSERY_DIR"/nursery_config

for group_dir in "$JSON_DIR"/*; do

    if [ -d "$group_dir" ] && [ -n "$(ls "$group_dir")" ]; then

        # create tab for a given group of games
        echo "[$group_dir]" >> "$NURSERY_DIR"/nursery_config

        # iterate through each json for the current group
        for filename in "$group_dir"/*.json; do
            create_config_from_json "$filename" >> "$NURSERY_DIR"/nursery_config
        done
    fi
done

cd $BIN_PATH
./easyConfig "$NURSERY_DIR"/nursery_config $MODES

# send signal USR1 to joystickinput to switch to ANALOG MODE
killall -q -USR1 joystickinput

auto_regen_tmp_update
