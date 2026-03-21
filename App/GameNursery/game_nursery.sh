#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Disable idle/shutdown timer during game downloads
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

##### CONSTANTS #####

CONFIG_DIR="/mnt/SDCARD/Saves/GameNursery"
RELEASE_URL="https://github.com/spruceUI/Ports-and-Free-Games/releases/download/Nursery"
CONFIG_URL="$RELEASE_URL/nursery_config"
BOXART_URL="$RELEASE_URL/boxart.7z"
SYSTEMS_URL="$RELEASE_URL/systems.json"
CACHE_VALID_MINUTES=20

log_message "--DEBUG-- PATH: $PATH" -v
log_message "--DEBUG-- LD_LIBRARY_PATH: $LD_LIBRARY_PATH" -v

##### FUNCTIONS #####

bind_over_PORTS() {
    log_message "bind mounting A30PORTS as backing store over viewpoint PORTS"
    mkdir -p /mnt/SDCARD/Roms/A30PORTS
    mkdir -p /mnt/SDCARD/Roms/PORTS
    mount --bind /mnt/SDCARD/Roms/A30PORTS /mnt/SDCARD/Roms/PORTS
}

unbind_PORTS() {
    log_message "unmounting A30PORTS from atop PORTS"
    umount /mnt/SDCARD/Roms/PORTS
}

is_wifi_connected() {
    if ping -c 3 github.com > /dev/null 2>&1; then
        log_message "Github ping successful; device is online."
        return 0
    else
        log_and_display_message "Github ping failed; device is offline. Aborting."
        return 1
    fi
}

show_slideshow_if_first_run() {
    if ! flag_check "nursery_accessed"; then
        /mnt/SDCARD/App/GameNursery/first_run.sh
        flag_add "nursery_accessed"
    fi
}

is_cache_valid() {
    local config_file="$CONFIG_DIR/nursery_config"

    if [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
        log_message "Game Nursery: nursery_config missing or empty."
        return 1
    fi

    if ! jq empty "$config_file" >/dev/null 2>&1; then
        log_message "Game Nursery: nursery_config is invalid JSON."
        return 1
    fi

    file_age_minutes=$(( ($(date +%s) - $(date -r "$config_file" +%s)) / 60 ))
    if [ "$file_age_minutes" -ge "$CACHE_VALID_MINUTES" ]; then
        log_message "Game Nursery: Cache expired ($file_age_minutes minutes old)."
        return 1
    fi

    log_message "Game Nursery: Cache is valid ($file_age_minutes minutes old)."
    return 0
}

download_nursery_assets() {
    mkdir -p "$CONFIG_DIR"

    log_and_display_message "Downloading game catalog..."
    if ! wget --quiet --no-check-certificate --max-redirect=20 -O "$CONFIG_DIR/nursery_config" "$CONFIG_URL"; then
        log_and_display_message "Unable to download game catalog. Please try again later."
        rm -f "$CONFIG_DIR/nursery_config" 2>/dev/null
        sleep 3
        exit 1
    fi
    log_message "Game Nursery: nursery_config downloaded successfully"

    log_and_display_message "Downloading system info..."
    if ! wget --quiet --no-check-certificate --max-redirect=20 -O "$CONFIG_DIR/systems.json" "$SYSTEMS_URL"; then
        log_message "Game Nursery: Failed to download systems.json (non-fatal)"
        rm -f "$CONFIG_DIR/systems.json" 2>/dev/null
    fi

    log_and_display_message "Downloading game artwork..."
    if wget --quiet --no-check-certificate --max-redirect=20 -O "/tmp/boxart.7z" "$BOXART_URL"; then
        mkdir -p "$CONFIG_DIR/Imgs"
        cd "$CONFIG_DIR"
        if 7zr x -y -scsUTF-8 "/tmp/boxart.7z" >/dev/null 2>&1; then
            log_message "Game Nursery: Boxart extracted successfully"
        else
            log_message "Game Nursery: Failed to extract boxart archive"
        fi
        rm -f "/tmp/boxart.7z" 2>/dev/null
    else
        log_message "Game Nursery: Failed to download boxart (non-fatal)"
        rm -f "/tmp/boxart.7z" 2>/dev/null
    fi
}

filter_config_for_platform() {
    if [ "$PLATFORM" != "A30" ]; then
        log_message "Game Nursery: Filtering out Ports (platform is $PLATFORM, not A30)"
        jq 'with_entries(select(.key | startswith("Ports/") | not))' \
            "$CONFIG_DIR/nursery_config" > "$CONFIG_DIR/nursery_config.tmp" \
            && mv "$CONFIG_DIR/nursery_config.tmp" "$CONFIG_DIR/nursery_config"
    fi
}

apply_system_icons() {
    jq -r 'keys[] | select(. != "descriptions") | split("/")[0]' "$CONFIG_DIR/nursery_config" | sort -u |
    while read -r group; do
        get_system_icon_from_theme "$group"
    done
}

get_system_icon_from_theme() {
    local category="$1"
    local systems_file="$CONFIG_DIR/systems.json"
    local current_theme icon_name emu_name selected_icon ext
    local theme_dir fallback_dir dest_path
    local config
    config=$(get_config_path)

    current_theme="$(jq -r '.theme // "spruce"' "$config")"

    # Read icon and emu mappings from systems.json
    if [ ! -f "$systems_file" ]; then
        log_message "Game Nursery: systems.json not found, cannot resolve icon for '$category'"
        return 1
    fi

    icon_name="$(jq -r --arg cat "$category" '.[$cat].icon // empty' "$systems_file")"
    emu_name="$(jq -r --arg cat "$category" '.[$cat].emu // empty' "$systems_file")"

    if [ -z "$icon_name" ] || [ -z "$emu_name" ]; then
        log_message "Game Nursery: No system mapping found for '$category'"
        return 1
    fi

    theme_dir="/mnt/SDCARD/Themes/${current_theme}/icons"
    fallback_dir="/mnt/SDCARD/Emu/${emu_name}"

    if   [ -e "${theme_dir}/sel/${icon_name}.qoi" ]; then selected_icon="${theme_dir}/sel/${icon_name}.qoi"
    elif [ -e "${theme_dir}/sel/${icon_name}.png" ]; then selected_icon="${theme_dir}/sel/${icon_name}.png"
    elif [ -e "${theme_dir}/${icon_name}.qoi" ];     then selected_icon="${theme_dir}/${icon_name}.qoi"
    elif [ -e "${theme_dir}/${icon_name}.png" ];     then selected_icon="${theme_dir}/${icon_name}.png"
    elif [ -e "${fallback_dir}/${icon_name}_sel.qoi" ]; then selected_icon="${fallback_dir}/${icon_name}_sel.qoi"
    elif [ -e "${fallback_dir}/${icon_name}_sel.png" ]; then selected_icon="${fallback_dir}/${icon_name}_sel.png"
    elif [ -e "${fallback_dir}/${icon_name}.qoi" ];  then selected_icon="${fallback_dir}/${icon_name}.qoi"
    elif [ -e "${fallback_dir}/${icon_name}.png" ];  then selected_icon="${fallback_dir}/${icon_name}.png"
    else return 1
    fi

    ext="${selected_icon##*.}"
    dest_path="/mnt/SDCARD/Saves/GameNursery/Imgs/${category}.${ext}"
    mkdir -p "/mnt/SDCARD/Saves/GameNursery/Imgs"
    cp -f "$selected_icon" "$dest_path"
    log_message "Game Nursery: Copied system icon for '$category' from '$selected_icon' → '$dest_path'"
}


##### MAIN EXECUTION #####

[ "$PLATFORM" = "A30" ] && bind_over_PORTS

start_pyui_message_writer
show_slideshow_if_first_run
log_and_display_message "Welcome to the spruceOS Game Nursery, where you can pick the freshest homegrown games! Please wait..."

if ! is_wifi_connected; then sleep 3; exit 1; fi

if ! is_cache_valid; then
    download_nursery_assets
    filter_config_for_platform
    apply_system_icons
fi

RESULT_FILE="/mnt/SDCARD/App/PyUI/selection.txt"
rm -f "$RESULT_FILE"

display_option_list "$CONFIG_DIR/nursery_config"

while true; do
    if [ -f "$RESULT_FILE" ]; then
        content=$(cat "$RESULT_FILE" 2>/dev/null)

        if [ "$content" = "EXIT" ]; then
            log_and_display_message "happy gaming.........."
            sleep 2
            break
        else
            log_message "$content"
            # Execute the content of the file as a command
            eval "$content"
            # Remove the file after running
            rm -f "$RESULT_FILE"
            display_option_list "$CONFIG_DIR/nursery_config"
        fi
    fi

done

touch /mnt/SDCARD/App/PyUI/pyui_resize_boxart_trigger

[ "$PLATFORM" = "A30" ] && unbind_PORTS
