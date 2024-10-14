#! /bin/sh

# Spruce updater: checks for an update file and applies them if found

DISPLAY="/mnt/SDCARD/Updater/bin/display_text.elf"
UPDATE_FILE=""
LOG_FILE="/mnt/SDCARD/Updater/updater.log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Simplified display function
display() {
    local text="$1"
    local delay="${2:-0}"
    local size="${3:-30}"
    local position="${4:-center}"
    local align="${5:-middle}"
    local width="${6:-600}"
    local color="${7:-ffffff}"
    local image="/mnt/SDCARD/miyoo/res/imgs/displayText.png"

    # Kill any existing display processes
    pkill -f "$DISPLAY"

    if [ "$delay" = "0" ]; then
        $DISPLAY "$image" "$text" "$delay" "$size" "$position" "$align" "$width" "${color:0:2}" "${color:2:2}" "${color:4:2}" &
    else
        $DISPLAY "$image" "$text" "$delay" "$size" "$position" "$align" "$width" "${color:0:2}" "${color:2:2}" "${color:4:2}"
    fi
}

# Start logging
log_message "Update process started"

display "Checking for update"
log_message "Displayed 'Checking for update' message"

echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Create fresh updater.log and start logging
echo "Update process started" > "$LOG_FILE"
exec >> "$LOG_FILE" 2>&1

# Check battery level
log_message "Checking battery level"
BATTERY_CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
log_message "Current battery level: $BATTERY_CAPACITY%"

if [ "$BATTERY_CAPACITY" -lt 30 ]; then
    log_message "Battery level too low for update"
    display "Battery too low for update
    Please charge to at least 30%" 5
    exit 1
fi

# Find update 7z file
log_message "Searching for update file"
UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)
log_message "Found update file: $UPDATE_FILE"

if [ -z "$UPDATE_FILE" ]; then
    log_message "No update file found"
    display "No update file found" 5
    exit 1
fi

# Extract version from update file
log_message "Extracting version from update file"
UPDATE_VERSION=$(echo "$UPDATE_FILE" | sed -n 's/.*spruceV\([0-9.]*\)\.7z/\1/p')
log_message "Extracted update version: $UPDATE_VERSION"

# Check current version
CURRENT_VERSION_FILE="/mnt/SDCARD/spruce/spruce"
log_message "Checking current version file: $CURRENT_VERSION_FILE"
if [ -f "$CURRENT_VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$CURRENT_VERSION_FILE")
    log_message "Current version: $CURRENT_VERSION"
else
    CURRENT_VERSION="2.3.0"
    log_message "Current version file not found, using default: $CURRENT_VERSION"
fi

# Compare versions using awk
log_message "Comparing versions: $UPDATE_VERSION vs $CURRENT_VERSION"
if [ "$(echo "$UPDATE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" = "$CURRENT_VERSION" ]; then
    log_message "Current version is up to date"
    display "Current version is up to date" 5
    exit 0
fi

# Verify update file contents
log_message "Verifying update file contents"
if [ ! -f "$UPDATE_FILE" ]; then
    log_message "Update file not found: $UPDATE_FILE"
    display "Update file not found" 5
    exit 1
fi

log_message "Checking file permissions"
ls -l "$UPDATE_FILE" >> "$LOG_FILE"

# Restore backup
/mnt/SDCARD/App/spruceRestore/spruceRestore.sh

# Delete all folders and files except Updater, update zip, BIOS, Roms, Saves, miyoo/app, and miyoo/lib
PERFORM_DELETION=false

if [ "$PERFORM_DELETION" = true ]; then
    log_message "Deleting unnecessary folders and files"
    display "Preparing for update..."
    cd /mnt/SDCARD

    # Explicitly delete .config and .tmp_update folders
    log_message "Deleting .config folder"
    rm -rf .config
    log_message "Deleting .tmp_update folder"
    rm -rf .tmp_update

    for item in *; do
        if [ "$item" != "Updater" ] && [ "$item" != "$(basename "$UPDATE_FILE")" ] && \
           [ "$item" != "BIOS" ] && [ "$item" != "Roms" ] && [ "$item" != "Saves" ] && [ "$item" != "Themes" ]; then
            if [ "$item" = "miyoo" ]; then
                log_message "Handling miyoo folder"
                find "$item" -mindepth 1 -maxdepth 1 ! -name "app" ! -name "lib" -exec rm -rf {} +
            else
                log_message "Deleting: $item"
                rm -rf "$item"
            fi
        fi
    done
    log_message "Deletion process completed"
else
    log_message "Skipping deletion process"
    display "Skipping file deletion..."
fi

# Extract update file
log_message "Extracting update file"
cd /mnt/SDCARD
log_message "Current directory: $(pwd)"
log_message "Extracting update file: $UPDATE_FILE"

display "Extracting update..."

if ! 7zr x -y -scsUTF-8 "$UPDATE_FILE" >> "$LOG_FILE" 2>&1; then
    log_message "Warning: Some files may have been skipped during extraction. Check $LOG_FILE for details."
    display "Update extraction completed with warnings" 5
else
    log_message "Extraction process completed successfully"
    display "Update extraction completed" 5
fi

# Verify extraction success
for dir in .tmp_update spruce miyoo; do
    if [ ! -d "$dir" ]; then
        log_message "Extraction verification failed: $dir missing"
        display "Update extraction incomplete: $dir" 5
        exit 1
    fi
    
    if [ -z "$(ls -A "$dir")" ]; then
        log_message "Extraction verification failed: $dir is empty"
        display "Update extraction incomplete: $dir empty" 5
        exit 1
    fi
done

log_message "Update file extracted successfully"
display "Update complete" 5

DELETE_UPDATE=false
if [ "$DELETE_UPDATE" = true ]; then
    log_message "Deleting update file"
    rm "$UPDATE_FILE"
    log_message "Update file deleted"
fi

# Restore backup
/mnt/SDCARD/App/spruceRestore/spruceRestore.sh

# Reboot device
killall -9 main
killall -9 runtime.sh
killall -9 principal.sh
killall -9 MainUI

poweroff