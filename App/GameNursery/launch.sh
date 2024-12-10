#!/bin/sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
NURSERY_DIR="/mnt/SDCARD/App/GameNursery"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"
JSON_DIR="/mnt/SDCARD/Saves/nursery"

# Copy of flag_check in helperFunctions.sh
# Here to keep launch time short
flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}" ] || [ -f "$FLAGS_DIR/${flag_name}.lock" ]; then
        return 0
    else
        return 1
    fi
}

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


    if ! grep -q "\[$grouping\]" "$NURSERY_DIR"/nursery_config; then
        echo "\[$grouping\]"
    fi

    echo "\"\" \"$display_name\" \"\|\" \"run\|off\" \"echo -n off\" \"\" \"\""
    echo "\@$description"

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

echo "" > "$NURSERY_DIR"/nursery_config

for filename in "$JSON_DIR"/*/*.json; do

    create_config_from_json "$filename" >> "$NURSERY_DIR"/nursery_config

done


cd $BIN_PATH
./easyConfig "$NURSERY_DIR"/nursery_config $MODES

# send signal USR1 to joystickinput to switch to ANALOG MODE
killall -q -USR1 joystickinput

auto_regen_tmp_update
