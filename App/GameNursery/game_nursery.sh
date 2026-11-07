#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Disable idle/shutdown timer during game downloads
killall -q idlemon 2>/dev/null
killall -q idle_watchdog.sh 2>/dev/null

##### CONSTANTS #####

CONFIG_DIR="/mnt/SDCARD/Saves/GameNursery"
RELEASE_URL="https://github.com/spruceUI/Ports-and-Free-Games/releases/download/Nursery"
CONFIG_URL="$RELEASE_URL/nursery_config_v2"
BOXART_URL="$RELEASE_URL/boxart.7z"
SYSTEMS_URL="$RELEASE_URL/systems.json"
CACHE_VALID_MINUTES=20

log_message "--DEBUG-- PATH: $PATH" -v
log_message "--DEBUG-- LD_LIBRARY_PATH: $LD_LIBRARY_PATH" -v

##### FUNCTIONS #####

is_wifi_connected() {
    if internet_reachable https://github.com; then
        log_message "GitHub reachable; device is online."
        return 0
    else
        log_and_display_message "Could not reach GitHub; device is offline. Aborting."
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
    local config_file="$CONFIG_DIR/nursery_config_v2"

    if [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
        log_message "Game Nursery: nursery_config_v2 missing or empty."
        return 1
    fi

    if ! jq empty "$config_file" >/dev/null 2>&1; then
        log_message "Game Nursery: nursery_config_v2 is invalid JSON."
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
    if ! download_url_to_file "$CONFIG_URL" "$CONFIG_DIR/nursery_config_v2"; then
        log_and_display_message "Unable to download game catalog. Please try again later."
        rm -f "$CONFIG_DIR/nursery_config_v2" 2>/dev/null
        sleep 3
        exit 1
    fi
    log_message "Game Nursery: nursery_config_v2 downloaded successfully"

    log_and_display_message "Downloading system info..."
    if ! download_url_to_file "$SYSTEMS_URL" "$CONFIG_DIR/systems.json"; then
        log_message "Game Nursery: Failed to download systems.json (non-fatal)"
        rm -f "$CONFIG_DIR/systems.json" 2>/dev/null
    fi

    log_and_display_message "Downloading game artwork..."
    if download_url_to_file "$BOXART_URL" "/tmp/boxart.7z"; then
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
            "$CONFIG_DIR/nursery_config_v2" > "$CONFIG_DIR/nursery_config_v2.tmp" \
            && mv "$CONFIG_DIR/nursery_config_v2.tmp" "$CONFIG_DIR/nursery_config_v2"
    fi
}

apply_system_icons() {
    jq -r 'keys[] | select(. != "descriptions") | split("/")[0]' "$CONFIG_DIR/nursery_config_v2" | sort -u |
    while read -r group; do
        get_system_icon_from_theme "$group"
    done
}

find_highest_resolution_icon_dir() {
    local theme_root="$1"
    local icon_dir dimensions width height area max_area=0 highest_dir=""

    for icon_dir in "${theme_root}"/icons_*x*; do
        [ -d "$icon_dir" ] || continue
        dimensions="${icon_dir##*/icons_}"
        case "$dimensions" in
            *x*) width="${dimensions%x*}"; height="${dimensions#*x}" ;;
            *) continue ;;
        esac
        case "$width:$height" in
            *[!0-9:]*|:*|*:) continue ;;
        esac

        width="${width#"${width%%[!0]*}"}"
        height="${height#"${height%%[!0]*}"}"
        [ -n "$width" ] && [ -n "$height" ] || continue
        [ "$width" -gt 0 ] && [ "$height" -gt 0 ] || continue
        area=$((width * height))
        if [ "$area" -gt "$max_area" ]; then
            max_area="$area"
            highest_dir="$icon_dir"
        fi
    done

    [ -n "$highest_dir" ] || return 1
    printf '%s\n' "$highest_dir"
}

find_first_existing_icon() {
    local candidate
    for candidate in "$@"; do
        if [ -e "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

get_system_icon_from_theme() {
    local category="$1"
    local systems_file="$CONFIG_DIR/systems.json"
    local current_theme icon_name emu_name selected_icon="" ext
    local theme_root theme_dir resolution_theme_dir fallback_dir dest_path
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

    if [ -z "$icon_name" ]; then
        log_message "Game Nursery: No system mapping found for '$category'"
        return 1
    fi

    theme_root="/mnt/SDCARD/Themes/${current_theme}"
    theme_dir="${theme_root}/icons"
    resolution_theme_dir="$(find_highest_resolution_icon_dir "$theme_root")"
    if [ -n "$resolution_theme_dir" ]; then
        log_message "Game Nursery: Using highest-resolution theme icon folder '$resolution_theme_dir'"
    fi
    fallback_dir="/mnt/SDCARD/Emu/${emu_name}"

    if [ -n "$resolution_theme_dir" ]; then
        selected_icon="$(find_first_existing_icon \
            "${resolution_theme_dir}/sel/${icon_name}.qoi" \
            "${resolution_theme_dir}/sel/${icon_name}.png" \
            "${resolution_theme_dir}/${icon_name}.qoi" \
            "${resolution_theme_dir}/${icon_name}.png")"
    fi
    if [ -z "$selected_icon" ]; then
        selected_icon="$(find_first_existing_icon \
            "${theme_dir}/sel/${icon_name}.qoi" \
            "${theme_dir}/sel/${icon_name}.png" \
            "${theme_dir}/${icon_name}.qoi" \
            "${theme_dir}/${icon_name}.png")"
    fi
    if [ -z "$selected_icon" ] && [ -n "$emu_name" ]; then
        selected_icon="$(find_first_existing_icon \
            "${fallback_dir}/${icon_name}_sel.qoi" \
            "${fallback_dir}/${icon_name}_sel.png" \
            "${fallback_dir}/${icon_name}.qoi" \
            "${fallback_dir}/${icon_name}.png")"
    fi
    if [ -z "$selected_icon" ] && [ -n "$resolution_theme_dir" ]; then
        selected_icon="$(find_first_existing_icon \
            "${resolution_theme_dir}/app/${icon_name}.qoi" \
            "${resolution_theme_dir}/app/${icon_name}.png")"
    fi
    if [ -z "$selected_icon" ]; then
        selected_icon="$(find_first_existing_icon \
            "${theme_dir}/app/${icon_name}.qoi" \
            "${theme_dir}/app/${icon_name}.png")"
    fi
    [ -n "$selected_icon" ] || return 1

    ext="${selected_icon##*.}"
    dest_path="/mnt/SDCARD/Saves/GameNursery/Imgs/${category}.${ext}"
    mkdir -p "/mnt/SDCARD/Saves/GameNursery/Imgs"
    cp -f "$selected_icon" "$dest_path"
    log_message "Game Nursery: Copied system icon for '$category' from '$selected_icon' → '$dest_path'"
}


##### MAIN EXECUTION #####


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

display_option_list "$CONFIG_DIR/nursery_config_v2"

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
            display_option_list "$CONFIG_DIR/nursery_config_v2"
        fi
    fi

done

touch /mnt/SDCARD/App/PyUI/pyui_resize_boxart_trigger
