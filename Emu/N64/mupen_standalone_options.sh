#!/bin/sh
# Mupen64Plus Standalone Options Menu
# Launched from N64 config.json launchlist
# Uses display_option_list to present settings, writes to mupen64plus.cfg

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SETTINGS="/mnt/SDCARD/Emu/N64/standalone_settings.json"
RESULT_FILE="/mnt/SDCARD/App/PyUI/selection.txt"
SELF="/mnt/SDCARD/Emu/N64/mupen_standalone_options.sh"

# Initialize settings file if missing
if [ ! -f "$SETTINGS" ]; then
    cat > "$SETTINGS" << 'ENDJSON'
{
    "video_plugin": "rice",
    "frameskip": "0",
    "cpu_emulator": "2",
    "expansion_pak": "1"
}
ENDJSON
fi

# Read a setting
get_setting() {
    jq -r ".$1" "$SETTINGS"
}

# Write a setting
set_setting() {
    local tmp=$(mktemp)
    jq ".$1 = \"$2\"" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

# Cycle to next value in a list
cycle_value() {
    local current="$1"
    shift
    local first="$1"
    local found=0
    for val in "$@"; do
        if [ "$found" = "1" ]; then
            echo "$val"
            return
        fi
        if [ "$val" = "$current" ]; then
            found=1
        fi
    done
    echo "$first"  # wrap around
}

# Human-readable labels
label_plugin() {
    case "$1" in
        rice) echo "Rice" ;;
        glide64mk2) echo "Glide64mk2" ;;
        gliden64) echo "GLideN64" ;;
        *) echo "$1" ;;
    esac
}

label_frameskip() {
    case "$1" in
        0) echo "Off" ;;
        1) echo "Skip 1" ;;
        2) echo "Skip 2" ;;
        auto) echo "Auto" ;;
        *) echo "$1" ;;
    esac
}

label_cpu() {
    case "$1" in
        0) echo "Pure Interpreter" ;;
        1) echo "Cached Interpreter" ;;
        2) echo "Dynamic Recompiler" ;;
        *) echo "$1" ;;
    esac
}

label_expansion() {
    case "$1" in
        0) echo "Disabled (4MB)" ;;
        1) echo "Enabled (8MB)" ;;
        *) echo "$1" ;;
    esac
}

# Handle a setting change
do_cycle() {
    case "$1" in
        video_plugin)
            local cur=$(get_setting video_plugin)
            local next=$(cycle_value "$cur" rice glide64mk2 gliden64)
            set_setting video_plugin "$next"
            ;;
        frameskip)
            local cur=$(get_setting frameskip)
            local next=$(cycle_value "$cur" 0 auto 1 2)
            set_setting frameskip "$next"
            ;;
        cpu_emulator)
            local cur=$(get_setting cpu_emulator)
            local next=$(cycle_value "$cur" 2 1 0)
            set_setting cpu_emulator "$next"
            ;;
        expansion_pak)
            local cur=$(get_setting expansion_pak)
            local next=$(cycle_value "$cur" 1 0)
            set_setting expansion_pak "$next"
            ;;
    esac

        # Settings applied at launch time by mupen_functions.sh
}


# Build the menu JSON
build_menu() {
    local vp=$(label_plugin "$(get_setting video_plugin)")
    local fs=$(label_frameskip "$(get_setting frameskip)")
    local cpu=$(label_cpu "$(get_setting cpu_emulator)")
    local exp=$(label_expansion "$(get_setting expansion_pak)")

    cat > /tmp/mupen_options.json << ENDJSON
{
    "Video Plugin: $vp": "$SELF cycle video_plugin",
    "Frameskip: $fs": "$SELF cycle frameskip",
    "CPU Mode: $cpu": "$SELF cycle cpu_emulator",
    "Expansion Pak: $exp": "$SELF cycle expansion_pak",
    "Back": "EXIT"
}
ENDJSON
}

##### MAIN #####

case "$1" in
    cycle)
        # Called by display_option_list eval — cycle a setting and exit
        do_cycle "$2"
        exit 0
        ;;
esac

# Interactive menu loop
start_pyui_message_writer
log_and_display_message "Mupen64Plus Standalone Options"
sleep 1

rm -f "$RESULT_FILE"
build_menu
display_option_list /tmp/mupen_options.json

while true; do
    if [ -f "$RESULT_FILE" ]; then
        content=$(cat "$RESULT_FILE" 2>/dev/null)

        if [ "$content" = "EXIT" ]; then
            break
        else
            eval "$content"
            rm -f "$RESULT_FILE"
            build_menu
            display_option_list /tmp/mupen_options.json
        fi
    fi
    sleep 0.1
done

rm -f /tmp/mupen_options.json
