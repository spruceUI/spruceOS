#!/bin/sh

# -------------------- UPGRADE SCRIPT TEMPLATE --------------------
# Instructions:
# 1. Set the TARGET_VERSION to the version you're upgrading to.
# 2. Add your file updates in the designated section using the update_file function.
# 3. Ensure all paths are correct for your specific upgrade scenario.
# 4. Add any additional upgrade steps as needed.

# Define the target version for this upgrade script
TARGET_VERSION="X.Y.Z"  # Replace X.Y.Z with your target version number

/mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Source the helper functions
HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# Function to update specific settings in a file
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

# -------------------- FILE UPDATES --------------------
# Add your file updates here using the update_file function
# Format: update_file "file_path" "setting1=value1" "setting2=value2" ...
# Example:
# update_file "/path/to/config.cfg" \
#     "setting1 = \"value1\"" \
#     "setting2 = \"value2\"" \
#     "setting3 = \"value3\""

# Update RetroArch main configuration
update_file "/mnt/SDCARD/RetroArch/retroarch.cfg" \
    "xmb_menu_color_theme = \"15\"" \
    "xmb_alpha_factor = \"100\"" \
    "savestate_thumbnail_enable = \"true\""

# Update RetroArch no-hotkey profile configuration
update_file "/mnt/SDCARD/RetroArch/nohotkeyprofile/retroarch.cfg" \
    "savestate_thumbnail_enable = \"true\""

# Update RetroArch hotkey profile configuration
update_file "/mnt/SDCARD/RetroArch/hotkeyprofile/retroarch.cfg" \
    "savestate_thumbnail_enable = \"true\""

# -------------------- ADDITIONAL UPGRADE STEPS --------------------
# Add any additional upgrade steps here, such as:
# - Creating new directories
# - Copying files
# - Running specific commands
# Example:
# mkdir -p /mnt/SDCARD/new_directory
# cp /path/to/source/file /path/to/destination/file
# custom_command_or_script

# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
