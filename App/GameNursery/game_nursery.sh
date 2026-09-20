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
REQUIREMENTS_URL="$RELEASE_URL/nursery_requirements.json"
CACHE_VALID_MINUTES=20

log_message "--DEBUG-- PATH: $PATH" -v
log_message "--DEBUG-- LD_LIBRARY_PATH: $LD_LIBRARY_PATH" -v

##### FUNCTIONS #####

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
    if ! download_url_to_file "$CONFIG_URL" "$CONFIG_DIR/nursery_config"; then
        log_and_display_message "Unable to download game catalog. Please try again later."
        rm -f "$CONFIG_DIR/nursery_config" 2>/dev/null
        sleep 3
        exit 1
    fi
    log_message "Game Nursery: nursery_config downloaded successfully"

    log_and_display_message "Downloading system info..."
    if ! download_url_to_file "$SYSTEMS_URL" "$CONFIG_DIR/systems.json"; then
        log_message "Game Nursery: Failed to download systems.json (non-fatal)"
        rm -f "$CONFIG_DIR/systems.json" 2>/dev/null
    fi

    # Optional: what an entry needs from the device. Only clients that know about this file
    # fetch it, so adding it to the catalog cannot disturb older spruce releases.
    if ! download_url_to_file "$REQUIREMENTS_URL" "$CONFIG_DIR/nursery_requirements.json"; then
        log_message "Game Nursery: Failed to download nursery_requirements.json (non-fatal)"
        rm -f "$CONFIG_DIR/nursery_requirements.json" 2>/dev/null
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
            "$CONFIG_DIR/nursery_config" > "$CONFIG_DIR/nursery_config.tmp" \
            && mv "$CONFIG_DIR/nursery_config.tmp" "$CONFIG_DIR/nursery_config"
    fi
}

# Hide entries this device cannot run. nursery_requirements.json maps a catalog key to what it
# needs, and every field is optional:
#
#   { "App/Aesthetic Spruce": { "arch": ["aarch64"],
#                               "devices": ["MIYOO_FLIP", "MAGICX_A133P"],
#                               "min_spruce": "4.3.0" } }
#
# arch is PLATFORM_ARCHITECTURE ("aarch64", "armhf"), devices are the tokens device_names()
# reports for this device, and min_spruce is the oldest release the entry supports. A check the
# device cannot answer is skipped rather than guessed, and any failure here keeps the catalog
# whole: a filter that cannot run must not empty the nursery.
filter_config_for_requirements() {
    requirements="$CONFIG_DIR/nursery_requirements.json"
    config="$CONFIG_DIR/nursery_config"

    [ -f "$requirements" ] || return 0
    if ! jq empty "$requirements" >/dev/null 2>&1; then
        log_message "Game Nursery: nursery_requirements.json is not valid JSON; keeping every entry"
        rm -f "$requirements"
        return 0
    fi

    names="$(device_names 2>/dev/null | jq -R . | jq -s -c .)"
    [ -n "$names" ] || names="[]"
    before="$(jq 'length' "$config" 2>/dev/null)"

    # No regex: some jq builds ship without oniguruma, so versions are split by hand.
    if jq --slurpfile requirements "$requirements" \
          --arg arch "${PLATFORM_ARCHITECTURE:-}" \
          --argjson names "$names" \
          --arg version "$(get_version 2>/dev/null)" '
        def num($v):
            ($v | split("-")[0] | split(".")) as $p
            | if ($p | length) == 0 then null
              else (($p[0] | tonumber? // 0) * 10000)
                   + ((($p[1] // "0") | tonumber? // 0) * 100)
                   + (($p[2] // "0") | tonumber? // 0)
              end;
        def wanted($need):
            (if ($need.arch // null) == null or ($arch | length) == 0 then true
             else ([$need.arch] | flatten | index($arch)) != null end)
            and (if ($need.devices // null) == null or ($names | length) == 0 then true
                 else ([$need.devices] | flatten) as $d
                      | ( ($d - $names) | length ) < ( $d | length ) end)
            and (if ($need.min_spruce // null) == null
                    or num($version) == null or num($need.min_spruce) == null then true
                 else num($version) >= num($need.min_spruce) end);
        ($requirements[0]) as $needs
        | with_entries(select(
              .key == "descriptions"
              or ($needs[.key] // null) == null
              or wanted($needs[.key])))
    ' "$config" > "$config.tmp"; then
        mv "$config.tmp" "$config"
        after="$(jq 'length' "$config" 2>/dev/null)"
        if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
            log_message "Game Nursery: hid $((before - after)) entr(y/ies) this device cannot run"
        fi
    else
        log_message "Game Nursery: could not apply entry requirements; keeping every entry"
        rm -f "$config.tmp" 2>/dev/null
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

    if [ -z "$icon_name" ]; then
        # Categories the catalog draws itself (App, for one) ship their tile in boxart.7z
        if [ -e "/mnt/SDCARD/Saves/GameNursery/Imgs/${category}.png" ] ||
            [ -e "/mnt/SDCARD/Saves/GameNursery/Imgs/${category}.qoi" ]; then
            log_message "Game Nursery: '$category' has no system mapping; keeping the catalog artwork" -v
            return 0
        fi
        log_message "Game Nursery: No system mapping found for '$category'"
        return 1
    fi

    theme_dir="/mnt/SDCARD/Themes/${current_theme}/icons"
    fallback_dir="/mnt/SDCARD/Emu/${emu_name}"

    if   [ -e "${theme_dir}/sel/${icon_name}.qoi" ]; then selected_icon="${theme_dir}/sel/${icon_name}.qoi"
    elif [ -e "${theme_dir}/sel/${icon_name}.png" ]; then selected_icon="${theme_dir}/sel/${icon_name}.png"
    elif [ -e "${theme_dir}/${icon_name}.qoi" ];     then selected_icon="${theme_dir}/${icon_name}.qoi"
    elif [ -e "${theme_dir}/${icon_name}.png" ];     then selected_icon="${theme_dir}/${icon_name}.png"
    elif [ -n "$emu_name" ] && [ -e "${fallback_dir}/${icon_name}_sel.qoi" ]; then selected_icon="${fallback_dir}/${icon_name}_sel.qoi"
    elif [ -n "$emu_name" ] && [ -e "${fallback_dir}/${icon_name}_sel.png" ]; then selected_icon="${fallback_dir}/${icon_name}_sel.png"
    elif [ -n "$emu_name" ] && [ -e "${fallback_dir}/${icon_name}.qoi" ];  then selected_icon="${fallback_dir}/${icon_name}.qoi"
    elif [ -n "$emu_name" ] && [ -e "${fallback_dir}/${icon_name}.png" ];  then selected_icon="${fallback_dir}/${icon_name}.png"
    elif [ -e "${theme_dir}/app/${icon_name}.qoi" ]; then selected_icon="${theme_dir}/app/${icon_name}.qoi"
    elif [ -e "${theme_dir}/app/${icon_name}.png" ]; then selected_icon="${theme_dir}/app/${icon_name}.png"
    else return 1
    fi

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
    filter_config_for_requirements
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

