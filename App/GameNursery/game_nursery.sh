#!/bin/sh

##### CONSTANTS #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
CONFIG_DIR="/tmp/nursery-config"
JSON_DIR="/tmp/nursery-json"
JSON_URL="https://github.com/spruceUI/Ports-and-Free-Games/releases/download/Singles/_info.7z"
DEV_JSON_URL="https://github.com/spruceUI/Ports-and-Free-Games/releases/download/Singles/_test.7z"

##### FUNCTIONS #####

check_battery() {
    CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"
    CAPACITY="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/capacity)"

    if [ "$CAPACITY" -lt 10 ] && [ "$CHARGING" -eq 0 ]; then
        log_message "Game Nursery: Device is below 10% battery and is not plugged in. Aborting."
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Cannot use Game Nursery while device battery is below 10%. Please plug in your A30, then try again."
        exit 1
    else
        log_message "Game Nursery: Device has at least 10% battery or is currently plugged in. Proceeding."
    fi
}

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
    log_message "Game Nursery: Device is online. Proceeding."
}

show_slideshow_if_first_run() {
    if ! flag_check "nursery_accessed"; then
        /mnt/SDCARD/App/GameNursery/first_run.sh
        flag_add "nursery_accessed"
    fi
}

get_latest_jsons() {
    mkdir "$JSON_DIR" 2>/dev/null
    cd "$JSON_DIR"
    rm -r ./* 2>/dev/null

    download_json() {
        local url="$1"
        if curl -s -k -L -o "$JSON_DIR/INFO.7z" "$url"; then
            return 0
        fi
        return 1
    }

    if [ -f "/mnt/SDCARD/spruce/flags/developer_mode" ]; then
        # Check if dev JSONs exist and try to download them
        if curl -s -k -L -I "$DEV_JSON_URL" 2>/dev/null | grep -q "200 OK" && download_json "$DEV_JSON_URL"; then
            log_message "Game Nursery: Dev-exclusive info cache downloaded"
        else
            log_message "Game Nursery: Dev JSONs not found, falling back to release JSONs"
            display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Dev JSON pack not found, falling back to release JSONs"
            
            if ! download_json "$JSON_URL"; then
                log_message "Game Nursery: Failed to download release info from $JSON_URL"
                display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to download latest info files from repository. Please try again later."
                exit 1
            fi
        fi
    else
        if ! download_json "$JSON_URL"; then
            log_message "Game Nursery: Failed to download release info from $JSON_URL"
            display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to download latest info files from repository. Please try again later."
            exit 1
        fi
        log_message "Game Nursery: Info cache downloaded successfully"
    fi

    if ! 7zr x -y -scsUTF-8 "$JSON_DIR/INFO.7z" >/dev/null 2>&1; then
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to extract latest game info files. Please try again later."
        rm -f "$JSON_DIR/INFO.7z" >/dev/null 2>&1
        log_message "Game Nursery: Failed to extract release info from INFO.7z file"
        exit 1
    fi
    log_message "Game Nursery: JSON extraction process completed successfully"
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

    mkdir "$CONFIG_DIR" 2>/dev/null
    cd "$CONFIG_DIR"
    rm -r ./* 2>/dev/null

    # initialize nursery_config with constant definitions.
    echo "\$TOGGLE=\/mnt\/SDCARD\/App\/GameNursery\/toggle_descriptions.sh\$" > "$CONFIG_DIR"/nursery_config
    echo "\$DOWNLOAD=\/mnt\/SDCARD\/App\/GameNursery\/download_game.sh\$" >> "$CONFIG_DIR"/nursery_config

    # loop through each folder of game jsons
    for group_dir in "$JSON_DIR"/*; do

        # make sure it's a non-empty directory before trying to do stuff
        if [ -d "$group_dir" ] && [ -n "$(ls "$group_dir")" ]; then

            # create tab for a given group of games
            tab_name="$(basename "$group_dir")"
            echo "[$tab_name]" >> "$CONFIG_DIR"/nursery_config

            # iterate through each json for the current group
            for filename in "$group_dir"/*.json; do
                interpret_json "$filename" >> "$CONFIG_DIR"/nursery_config
            done
        fi
    done
    log_message "Game Nursery: nursery_config constructed from game info JSONs."
}


##### MAIN EXECUTION #####

display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png" -t "Connecting to the spruce Game Nursery. Please wait.........."

check_battery
check_for_connection
show_slideshow_if_first_run
get_latest_jsons
construct_config

killall -q -USR2 joystickinput # kbd mode
cd $BIN_PATH && ./easyConfig "$CONFIG_DIR"/nursery_config
killall -q -USR1 joystickinput # analog mode
