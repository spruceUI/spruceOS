#!/bin/sh

# Define the target version for this upgrade script
TARGET_VERSION="2.3.0"

# Source the global functions
if [ -f /mnt/SDCARD/spruce/scripts/helperFunctions.sh ]; then
    . /mnt/SDCARD/spruce/scripts/helperFunctions.sh
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# Update specific settings in a file
# Usage: update_file "file_path" "setting1=value1" "setting2=value2" ...
update_file() {
    file="$1"
    shift
    
    for setting in "$@"; do
        if grep -q "${setting%%=*}" "$file"; then
            sed -i "s|^${setting%%=*}.*|$setting|" "$file"
        else
            echo "$setting" >> "$file"
        fi
    done
    
    log_message "Updated $file"
}

# Main execution
log_message "Starting upgrade to version $TARGET_VERSION"


# ----------------File Updates Here---------------- 
# Update specific files
update_file "/mnt/SDCARD/RetroArch/retroarch.cfg" \
    "xmb_menu_color_theme = \"15\"" \
    "xmb_alpha_factor = \"100\"" \
    "savestate_thumbnail_enable = \"true\""

update_file "/mnt/SDCARD/RetroArch/nohotkeyprofile/retroarch.cfg" \
    "savestate_thumbnail_enable = \"true\""

update_file "/mnt/SDCARD/RetroArch/hotkeyprofile/retroarch.cfg" \
    "savestate_thumbnail_enable = \"true\""



# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
