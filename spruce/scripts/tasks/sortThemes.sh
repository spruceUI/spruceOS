#!/bin/sh
if [ "$1" == "0" ]; then
    echo -n "Themes will be alphabetized on save and exit."
    return 0
fi

if [ "$1" == "1" ]; then
    echo -n "Use this to re-sort themes alphabetically."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh



# Add this new function before the main loop
update_theme_dates() {
    log_message "Theme Garden: Attempt to alphabetize themes"
    
    # Create temporary directory
    mkdir -p "/mnt/SDCARD/temp_themes"
    
    # First move all themes to temp directory
    for theme_dir in /mnt/SDCARD/Themes/*/; do
        [ -d "$theme_dir" ] || continue
        theme_name="$(basename "$theme_dir")"
        log_message "Theme Garden: Moving to temp: $theme_name"
        mv "$theme_dir" "/mnt/SDCARD/temp_themes/$theme_name"
    done
    
    # First move SPRUCE back if it exists
    if [ -d "/mnt/SDCARD/temp_themes/SPRUCE" ]; then
        log_message "Theme Garden: Moving SPRUCE back first"
        mv "/mnt/SDCARD/temp_themes/SPRUCE" "/mnt/SDCARD/Themes/SPRUCE"
    fi
    
    # Move the rest back in alphabetical order
    for theme_dir in /mnt/SDCARD/temp_themes/*/; do
        [ -d "$theme_dir" ] || continue
        theme_name="$(basename "$theme_dir")"
        log_message "Theme Garden: Moving back: $theme_name"
        mv "$theme_dir" "/mnt/SDCARD/Themes/$theme_name"
    done
    
    # Clean up
    rmdir "/mnt/SDCARD/temp_themes"
}

update_theme_dates