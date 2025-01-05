#!/bin/sh

# -------------------- UPGRADE SCRIPT TEMPLATE --------------------
# Instructions:
# 1. Set the TARGET_VERSION to the version you're upgrading to.
# 2. Add your file updates in the designated section using the update_file function.
# 3. Ensure all paths are correct for your specific upgrade scenario.
# 4. Add any additional upgrade steps as needed.

# Define the target version for this upgrade script
TARGET_VERSION="3.3.0"  # Replace X.Y.Z with your target version number

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

update_file "/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM/ppsspp.ini" \
    "MemStickInserted = True" \
    "AllowMappingCombos = True"

update_file "/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM/controls.ini" \
    "Up = 10-19" \
    "Down = 10-20" \
    "Left = 10-21" \
    "Right = 10-22" \
    "Circle = 10-190" \
    "Cross = 10-189" \
    "Square = 10-191" \
    "Triangle = 10-188" \
    "Start = 10-197" \
    "Select = 10-196" \
    "L = 10-193" \
    "R = 10-192" \
    "An.Up = 10-4003" \
    "An.Down = 10-4002" \
    "An.Left = 10-4001" \
    "An.Right = 10-4000" \
    "Fast-forward = 10-196:10-4010" \
    "SpeedToggle = 10-196:10-4008" \
    "Save State = 10-196:10-192" \
    "Load State = 10-196:10-193" \
    "Previous Slot = 10-196:10-21" \
    "Next Slot = 10-196:10-22" \
    "Screenshot = 10-196:10-190" \
    "Exit App = 10-196:10-189" \
    "Pause = 10-106" \
    "Hold = 10-4"

if setting_get "runGSAtBoot"; then
    update_file "/mnt/SDCARD/spruce/settings/spruce.cfg" "bootTo=1"
fi

# -------------------- ADDITIONAL UPGRADE STEPS --------------------
# Add any additional upgrade steps here, such as:
# - Creating new directories
# - Copying files
# - Running specific commands
# Example:
# mkdir -p /mnt/SDCARD/new_directory
# cp /path/to/source/file /path/to/destination/file
# custom_command_or_script

sed -i '/input_player1_btn_r2 = "-1"/d' "/mnt/SDCARD/RetroArch/.retroarch/config/remaps/Gambatte/Gambatte.rmp"
sed -i '/input_player1_btn_r2 = "-1"/d' "/mnt/SDCARD/RetroArch/.retroarch/config/remaps/gpSP/gpSP.rmp"
sed -i '/input_player1_btn_r2 = "-1"/d' "/mnt/SDCARD/RetroArch/.retroarch/config/remaps/mGBA/mGBA.rmp"

# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
