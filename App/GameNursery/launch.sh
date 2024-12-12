#!/bin/sh

##### CONSTANTS #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
NURSERY_DIR="/mnt/SDCARD/App/GameNursery"
JSON_DIR="/tmp/nursery"
JSON_URL="https://github.com/spruceUI/Ports-and-Free-Games/releases/download/INFO/INFO.7z"

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
    mkdir "$JSON_DIR" 2>/dev/null
    cd "$JSON_DIR"
    rm -r ./* 2>/dev/null

    # Download and parse the release info file
    if ! curl -s -k -L -o "$JSON_DIR/INFO.7z" "$JSON_URL"; then
        log_message "Game Nursery: Failed to download release info from $JSON_URL"
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to download latest info files from repository. Please try again later."
        exit 1
    fi

    if ! 7zr x -y -scsUTF-8 "$JSON_DIR/INFO.7z" >/dev/null 2>&1; then
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to extract latest game info files. Please try again later."
        rm -f "$JSON_DIR/INFO.7z" >/dev/null 2>&1
        log_message "Game Nursery: Failed to extract release info from INFO.7z file"
        exit 1
    else
        log_message "Extraction process completed successfully"
    fi
}

interpret_json() {

    json_file="$1"
    display_name="$(jq -r '.display' "$json_file")"
    file="$(jq -r '.file' "$json_file")"
    system="$(jq -r '.system' "$json_file")"
    description="$(jq -r '.description' "$json_file")"
    requires_files="$(jq -r '.requires_files' "$json_file")"
    # version="$(jq -r '.version' "$json_file")"

    # add notice that additional files are needed
    if [ "$requires_files" = "true" ]; then
        description="$description Requires additional files."
    fi

    # add line for specific game
    echo "\"\" \"$display_name\" \"|\" \"run|off\" \"echo -n off\" \"\$DOWNLOAD\$ '$json_file'|\" \"\$TOGGLE\$ '_VALUE_' '$json_file'\""

    # check whether game already installed
    if [ -f "/mnt/SDCARD/Roms/$system/$file" ]; then
        echo "@\"Already installed!\""
    else
        echo "@\"$description\""
    fi

}

construct_config() {

# initialize nursery_config with constant definitions.
echo "\$TOGGLE=\/mnt\/SDCARD\/App\/GameNursery\/toggle_descriptions.sh\$" > "$NURSERY_DIR"/nursery_config
echo "\$DOWNLOAD=\/mnt\/SDCARD\/App\/GameNursery\/download_game.sh\$" >> "$NURSERY_DIR"/nursery_config

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

display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png" -t "Connecting to the spruce Game Nursery. Please wait.........."

check_for_connection
get_latest_jsons
construct_config

killall -q -USR2 joystickinput # kbd mode
cd $BIN_PATH && ./easyConfig "$NURSERY_DIR"/nursery_config
killall -q -USR1 joystickinput # analog mode
