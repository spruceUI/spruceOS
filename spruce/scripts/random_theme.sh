#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


# Define constants and functions, and initialize variables.
THEME_DIR="/mnt/SDCARD/Themes"
ALREADY_APPLIED_LIST="/mnt/SDCARD/Saves/spruce/applied_random_themes.txt"
prev_theme=    # ensures this is empty unless intentionally set during execution of this script

get_full_list_of_installed_themes() {
    find "$THEME_DIR" -mindepth 1 -maxdepth 1 -type d
}

count_entries() {
    printf '%s\n' "$1" | wc -l
}

# Get installed themes
theme_list="$(get_full_list_of_installed_themes)"

# Remove themes already selected this cycle
if [ -s "$ALREADY_APPLIED_LIST" ] && [ -n "$theme_list" ]; then
    theme_list="$(printf '%s\n' "$theme_list" |
        grep -Fvx -f "$ALREADY_APPLIED_LIST")"
fi

# Count remaining themes
if [ -n "$theme_list" ]; then
    num_themes="$(count_entries "$theme_list")"
else
    num_themes=0
fi

# Reset history once all installed themes have been selected.
if [ "$num_themes" -eq 0 ]; then
    prev_theme="$(get_pyui_config_value ".theme" "SPRUCE")"
    : > "$ALREADY_APPLIED_LIST"
    theme_list="$(get_full_list_of_installed_themes)"
    num_themes="$(count_entries "$theme_list")"
fi

# Select a random remaining theme
random_num="$(awk -v n="$num_themes" 'BEGIN { srand(); print int(rand() * n) + 1 }')"
picked_theme="$(printf '%s\n' "$theme_list" | sed -n "${random_num}p")"
theme_name="$(basename "$picked_theme")"

# if the selected theme is the same as the previous one, fudge the numbers.
if [ -n "$prev_theme" ]; then
    if [ "$prev_theme" = "$theme_name" ]; then
        random_num=$((random_num % num_themes + 1))
        picked_theme="$(printf '%s\n' "$theme_list" | sed -n "${random_num}p")"
        theme_name="$(basename "$picked_theme")"
    fi
fi

# Apply the theme, then record the selection
if set_pyui_config_value ".theme" "$theme_name"; then
    printf '%s\n' "$picked_theme" >> "$ALREADY_APPLIED_LIST"
    log_message "random_theme.sh - Applied $theme_name theme."
    exit 0
else
    log_message "random_theme.sh - Failed to apply $theme_name theme."
    exit 1
fi