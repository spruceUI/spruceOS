#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

##### CONSTANTS #####

DOWNLOAD="/mnt/SDCARD/App/ThemeGarden/download_theme.sh"
CONFIG_DIR=/mnt/SDCARD/Saves/ThemeGarden
PREVIEW_PACK_URL="https://raw.githubusercontent.com/spruceUI/PyUI-Themes/main/Resources/theme_previews.7z"

##### FUNCTIONS #####

is_wifi_connected() {
    if ping -c 3 -W 2 1.1.1.1 > /dev/null 2>&1; then
        log_message "Cloudflare ping successful; device is online."
        return 0
    else
        log_and_display_message "Cloudflare ping failed; device is offline. Aborting."
        return 1
    fi
}

setup_previews() {
    local timestamp_file="$CONFIG_DIR/last_update"
    local max_age=1200 # 20 minutes in seconds
    local current_time=$(date +%s)
    local should_update=1

    # Check if timestamp exists and is recent
    if [ -f "$timestamp_file" ]; then
        local last_update=$(cat "$timestamp_file")
        local age=$((current_time - last_update))
        if [ $age -lt $max_age ]; then
            should_update=0
        fi
    fi

    # Update previews if needed
    if [ $should_update -eq 1 ] || [ ! -d "$CONFIG_DIR/previews" ] || [ -z "$(find "$CONFIG_DIR/previews" -name "*.png" 2>/dev/null)" ]; then
        log_and_display_message "Downloading theme previews.........."
        rm -rf "$CONFIG_DIR/previews"
        mkdir -p "$CONFIG_DIR/previews"

        if ! download_and_display_progress "$PREVIEW_PACK_URL" "$CONFIG_DIR/theme_previews.7z" "Theme Previews"; then
            log_and_display_message "Unable to download preview pack. Please try again later."
            return 1
        fi

        if ! 7zr x "$CONFIG_DIR/theme_previews.7z" -o"$CONFIG_DIR/previews" 2>&1; then
            log_and_display_message "Unable to extract theme previews from archive. Please try again later."
            rm -f "$CONFIG_DIR/theme_previews.7z"
            return 1
        fi
        rm -f "$CONFIG_DIR/theme_previews.7z"

        # Update timestamp
        echo "$current_time" >"$timestamp_file"
    fi

    # Final check if we have any preview files
    if [ -z "$(find "$CONFIG_DIR/previews" -name "*.png" 2>/dev/null)" ]; then
        log_and_display_message "No theme previews found!"
        return 1
    fi

    return 0    # hooray! we made it!
}

construct_config() {
    rm -rf "$CONFIG_DIR/Imgs"
    mkdir -p "$CONFIG_DIR/Imgs"
    echo "{" > "$CONFIG_DIR/garden.json"

    for theme in "$CONFIG_DIR/previews"/*.png ; do
        theme_name="$(basename "$theme" .png)"
        encoded_name=$(echo "$theme_name" | sed 's/ /%20/g' | sed "s/'/%27/g")
        mv "$theme" "$CONFIG_DIR/Imgs/"
        echo "\"$theme_name\": \"$DOWNLOAD '$encoded_name'\"," >> "$CONFIG_DIR/garden.json"
    done

    sed -i '$ s/,$//' "$CONFIG_DIR"/garden.json      # strip away final trailing comma
    echo "}" >> "$CONFIG_DIR/garden.json"
}

##### MAIN EXECUTION #####

mkdir -p "$CONFIG_DIR"

start_pyui_message_writer
log_and_display_message "Welcome to the spruceOS Theme Garden. We hope you enjoy your visit as you stop and smell the artwork. Please wait.........."

if ! is_wifi_connected; then sleep 3; exit 1; fi
if ! setup_previews; then sleep 3; exit 1; fi
construct_config

RESULT_FILE="/mnt/SDCARD/App/PyUI/selection.txt"
rm -f "$RESULT_FILE"

display_option_list "$CONFIG_DIR/garden.json"

while true; do
    if [ -f "$RESULT_FILE" ]; then
        content=$(cat "$RESULT_FILE" 2>/dev/null)
        
        if [ "$content" = "EXIT" ]; then
            log_and_display_message "happy theming.........."
            sleep 3
            break
        else
            log_message "$content"
            # Execute the content of the file as a command
            eval "$content"
            # Remove the file after running
            rm -f "$RESULT_FILE"
            display_option_list "$CONFIG_DIR/garden.json"
        fi
    fi

done

/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
