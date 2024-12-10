#!/bin/sh

##### CONSTANTS #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
NURSERY_DIR="/mnt/SDCARD/App/GameNursery"
JSON_DIR="/mnt/SDCARD/Saves/nursery"


##### FUNCTIONS #####

check_for_connection() {

    wifi_enabled="$(jq -r '.wifi' "/config/system.json")"
    if [ $wifi_enabled -eq 0 ]; then
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Wi-Fi not enabled. You must enable Wi-Fi to download free games."
        exit 1
    fi

    if ! ping -c 3 github.com > /dev/null 2>&1; then
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to connect to GitHub repository. Please check your connection and try again."
        exit 1
    fi
}

get_latest_jsons() {

    true

}



interpret_json() {

    json_file="$1"
    grouping="$(basename "$(dirname "$json_file")")"

    display_name="$(jq -r '.display' "$json_file")"
    file="$(jq -r '.file' "$json_file")"
    system="$(jq -r '.system' "$json_file")"
    description="$(jq -r '.description' "$json_file")"
    requires_files="$(jq -r '.requires_files' "$json_file")"
    version="$(jq -r '.version' "$json_file")"

    # add notice that additional files are needed
    if [ "$requires_files" = "true" ]; then
        description="$description Requires additional files."
    fi

    # add line for specific game
    echo "\"\" \"$display_name\" \"|\" \"run|off\" \"echo -n off\" \"\" \"\$TOGGLE\$ '_VALUE_' $json_file\""

    # check whether game already installed
    if [ -f "/mnt/SDCARD/Roms/$system/$file" ]; then
        echo "@\"Already installed!\""
    else
        echo "@\"$description\""
    fi

}

construct_config() {

# initialize nursery_config with constant definition.
echo "\$TOGGLE=\/mnt\/SDCARD\/App\/GameNursery\/toggle_descriptions.sh\$" > "$NURSERY_DIR"/nursery_config

# loop through each folder of game jsons
for group_dir in "$JSON_DIR"/*; do

    # make sure it's a non-empty directory before trying to do stuff
    if [ -d "$group_dir" ] && [ -n "$(ls "$group_dir")" ]; then

        # create tab for a given group of games
        tab_name="$(basename "$group_dir")"
        echo "[$tab_name]" >> "$NURSERY_DIR"/nursery_config

        # iterate through each json for the current group
        for filename in "$group_dir"/*.json; do
            interpret_json "$filename" >> "$NURSERY_DIR"/nursery_config
        done
    fi
done

}


##### MAIN EXECUTION #####

check_for_connection
get_latest_jsons
construct_config

killall -q -USR2 joystickinput # kbd mode
cd $BIN_PATH
./easyConfig "$NURSERY_DIR"/nursery_config
killall -q -USR1 joystickinput # analog mode
