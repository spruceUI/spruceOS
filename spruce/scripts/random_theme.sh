#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Define constants
THEME_DIR="/mnt/SDCARD/Themes"

# Get a list of themes
theme_list="$(find "$THEME_DIR" -mindepth 1 -maxdepth 1 -type d)"

# Count themes
num_themes="$(printf '%s\n' "$theme_list" | wc -l)"

# Get a random theme (1-based)
random_num="$(awk -v n="$num_themes" 'BEGIN { srand(); print int(rand() * n) + 1 }')"
picked_theme="$(printf '%s\n' "$theme_list" | sed -n "${random_num}p")"
theme_name="$(basename "$picked_theme")"

# Apply the picked theme
set_pyui_config_value ".theme" "$theme_name"
log_message "random_theme.sh - Applied $theme_name theme."