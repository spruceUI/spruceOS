#!/bin/sh

# -------------------- UPGRADE SCRIPT TEMPLATE --------------------
# Instructions:
# 1. Set the TARGET_VERSION to the version you're upgrading to.
# 2. Add your file updates in the designated section using the update_file function.
# 3. Ensure all paths are correct for your specific upgrade scenario.
# 4. Add any additional upgrade steps as needed.

# Define the target version for this upgrade script
TARGET_VERSION="3.3.1"  # Replace X.Y.Z with your target version number

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
# Remove boot_to=Game Switcher if it exists, this is to fix a bad migration for a few early adopters
CONFIG_FILE="/mnt/SDCARD/spruce/settings/spruce.cfg"
if [ -f "$CONFIG_FILE" ]; then
    sed -i '/^boot_to=Game Switcher$/d' "$CONFIG_FILE"
    log_message "Removed boot_to=Game Switcher from spruce.cfg if it existed"
fi


FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
# Update launch paths in favourite.json if it exists
if [ -f "$FAVOURITE_FILE" ]; then
    # Create a temporary file
    TEMP_FILE="${FAVOURITE_FILE}.tmp"
    
    # Process the file line by line
    while IFS= read -r line; do
        # Check if line contains old launch path pattern
        if echo "$line" | grep -q '"/mnt/SDCARD/Emu/.*/launch.sh"'; then
            # Replace the launch path pattern
            echo "$line" | sed 's|/launch.sh"|/../.emu_setup/standard_launch.sh"|' >> "$TEMP_FILE"
        else
            echo "$line" >> "$TEMP_FILE"
        fi
    done < "$FAVOURITE_FILE"
    
    # Replace original file with updated content
    mv "$TEMP_FILE" "$FAVOURITE_FILE"
    log_message "Updated launch paths in favourite.json"
fi

# -------------------- ADDITIONAL UPGRADE STEPS --------------------


# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
