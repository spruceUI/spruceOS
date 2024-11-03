#! /bin/sh

# Spruce updater: checks for an update file and applies them if found

DISPLAY="/mnt/SDCARD/Updater/bin/display_text.elf"
APP_DIR="/mnt/SDCARD/App/-Updater"
UPDATE_FILE=""
LOG_LOCATION="/mnt/SDCARD/Updater/updater.log"
CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"

. /mnt/SDCARD/Updater/updaterFunctions.sh

# Function to log messages
log_update_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_LOCATION"
}

# Simplified display function
display() {
    local text="$1"
    local delay="${2:-0}"
    local size="${3:-30}"
    local position="${4:-center}"
    local align="${5:-middle}"
    local width="${6:-600}"
    local color="${7:-dbcda7}"
    local image="/mnt/SDCARD/Updater/imgs/back.png"

    # Kill any existing display processes more safely
    ps | grep display_text.elf | grep -v grep | while read pid rest; do
        kill "$pid" 2>/dev/null
    done

    if [ "$delay" = "0" ]; then
        $DISPLAY "$image" "$text" "$delay" "$size" "$position" "$align" "$width" "${color:0:2}" "${color:2:2}" "${color:4:2}" "/mnt/SDCARD/Updater/bin/nunwen.ttf" 7f 7f 7f 0 2>/dev/null &
    else
        $DISPLAY "$image" "$text" "$delay" "$size" "$position" "$align" "$width" "${color:0:2}" "${color:2:2}" "${color:4:2}" "/mnt/SDCARD/Updater/bin/nunwen.ttf" 7f 7f 7f 0 2>/dev/null
    fi
}

# Start
log_update_message "Update process started"
display "Checking for update file..."
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Create fresh updater.log and start logging
echo "Update process started" >"$LOG_LOCATION"
exec >>"$LOG_LOCATION" 2>&1

# Find update 7z file
if ! check_for_update_file; then
    display "No update file found" 5
    sed -i 's|"label"|"#label"|' "$APP_DIR/config.json"
    exit 1
fi

UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)

# Check battery level
log_update_message "Checking battery level"
BATTERY_CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
log_update_message "Current battery level: $BATTERY_CAPACITY%"

if [ "$BATTERY_CAPACITY" -lt 30 ] && [ "$CHARGING" -eq 0 ]; then
    log_update_message "Battery level too low for update"
    display "Battery too low for update.
    Please charge to at least 30% or plug in your device." 5
    exit 1
fi

boost_processing

# Extract version from update file
log_update_message "Extracting version from update file"
UPDATE_VERSION=$(echo "$UPDATE_FILE" | sed -n 's/.*spruceV\([0-9.]*\)\.7z/\1/p')
log_update_message "Extracted update version: $UPDATE_VERSION"

# Check current version
CURRENT_VERSION_FILE="/mnt/SDCARD/spruce/spruce"
log_update_message "Checking current version file: $CURRENT_VERSION_FILE"
if [ -f "$CURRENT_VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$CURRENT_VERSION_FILE")
    log_update_message "Current version: $CURRENT_VERSION"
else
    CURRENT_VERSION="2.3.0"
    log_update_message "Current version file not found, using default: $CURRENT_VERSION"
fi
# Compare versions using awk
UPDATE_SAME_VERSION=true
log_update_message "Comparing versions: $UPDATE_VERSION vs $CURRENT_VERSION"
if [ "$UPDATE_SAME_VERSION" = true ] || [ "$(echo "$UPDATE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$CURRENT_VERSION" ]; then
    log_update_message "Proceeding with update"
else
    log_update_message "Current version is up to date"
    if ! check_installation_validity; then
        log_update_message "Bad installation detected"
        display "Detected current installation is invalid.
Allowing reinstall." 5
    else
        display "Current version is up to date" 5
        exit 0
    fi
fi

# Verify update file contents
log_update_message "Verifying update file contents"
if [ ! -f "$UPDATE_FILE" ]; then
    log_update_message "Update file not found: $UPDATE_FILE"
    display "Update file not found" 5
    exit 1
fi
# Verify the content of the 7z starts with /mnt/

if ! verify_7z_content "$UPDATE_FILE"; then
    display "Invalid update file structure" 5
    exit 1
fi

log_update_message "Checking file permissions"
ls -l "$UPDATE_FILE" >>"$LOG_LOCATION"

# Creating a backup of current install
display "Creating a backup of user data and configs..."
/mnt/SDCARD/App/spruceBackup/spruceBackup.sh --silent

# Delete all folders and files except Updater, update zip, BIOS, Roms, Saves, miyoo/app, and miyoo/lib
PERFORM_DELETION=true
echo heartbeat >/sys/devices/platform/sunxi-led/leds/led1/trigger &

if [ "$PERFORM_DELETION" = true ]; then
    log_update_message "Deleting unnecessary folders and files"
    display "Cleaning up your SD card..."
    cd /mnt/SDCARD

    # Explicitly delete .config and .tmp_update folders
    log_update_message "Deleting .config folder"
    rm -rf .config
    log_update_message "Deleting .tmp_update folder"
    rm -rf .tmp_update

    for item in *; do
        if [ "$item" != "Updater" ] && [ "$item" != "$(basename "$UPDATE_FILE")" ] &&
            [ "$item" != "BIOS" ] && [ "$item" != "Roms" ] && [ "$item" != "Saves" ] && [ "$item" != "Themes" ]; then
            if [ "$item" = "miyoo" ]; then
                log_update_message "Handling miyoo folder"
                find "$item" -mindepth 1 -maxdepth 1 ! -name "app" ! -name "lib" -exec rm -rf {} +
            else
                log_update_message "Deleting: $item"
                rm -rf "$item"
            fi
        fi
    done
    log_update_message "Deletion process completed"
    display "SD card cleaned up..." 2
else
    log_update_message "Skipping deletion process"
    display "Skipping file deletion..." 5
fi

# Extract update file
log_update_message "Extracting update file."
echo heartbeat >/sys/devices/platform/sunxi-led/leds/led1/trigger &
cd /mnt/SDCARD
log_update_message "Current directory: $(pwd)"
log_update_message "Extracting update file: $UPDATE_FILE"

display "Applying update. This should take around 5 minutes..."

if ! 7zr x -y -scsUTF-8 "$UPDATE_FILE" >>"$LOG_LOCATION" 2>&1; then
    log_update_message "Warning: Some files may have been skipped during extraction. Check $LOG_LOCATION for details."
    display "Update completed with warnings. Check the update log for details." 5
else
    log_update_message "Extraction process completed successfully"
    display "Update completed" 5
fi

# Verify extraction success
for dir in .tmp_update spruce miyoo; do
    if [ ! -d "$dir" ]; then
        log_update_message "Extraction verification failed: $dir missing"
        display "Update extraction incomplete: $dir" 5
        exit 1
    fi

    if [ -z "$(ls -A "$dir")" ]; then
        log_update_message "Extraction verification failed: $dir is empty"
        display "Update extraction incomplete: $dir empty" 5
        exit 1
    fi
done

log_update_message "Update file extracted successfully"
display "Now using spruce $UPDATE_VERSION" 2

DELETE_UPDATE=true
if [ "$DELETE_UPDATE" = true ]; then
    log_update_message "Deleting update file"
    rm "$UPDATE_FILE"
    log_update_message "Update file deleted"
fi

# Restore backup
display "Restoring user data..."
/mnt/SDCARD/App/spruceRestore/spruceRestore.sh --silent

display "Update complete. Shutting down...
You'll need to manually power back on" 3
echo 100 >/sys/devices/virtual/timed_output/vibrator/enable

# Reboot device
killall -9 runtime.sh
killall -9 principal.sh
killall -9 MainUI

log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
poweroff
