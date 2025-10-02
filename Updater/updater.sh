#! /bin/sh

# Spruce updater: checks for an update file and applies them if found

APP_DIR="/mnt/SDCARD/App/-Updater"
UPDATE_FILE=""
LOG_LOCATION="/mnt/SDCARD/Updater/updater.log"

. /mnt/SDCARD/Updater/updaterFunctions.sh
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

CHARGING="$(cat $BATTERY/online)"

# Function to log messages
log_update_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_LOCATION"
}

# Simplified display function
display() {
    DISPLAY="$BIN_DIR/display_text.elf"
    ACKNOWLEDGE_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayAcknowledge.png"

    if [ "$PLATFORM" = "Brick" ]; then
        width=960
        LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
    elif [ "$PLATFORM" = "SmartPro" ]; then
        width=1200
        LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
    else 
        width=600
    fi

    image="/mnt/SDCARD/Updater/imgs/back.png"
    text=" " 
            delay=0
    size=30 
    position=50 
    align="middle" 
    font="$BIN_DIR/nunwen.ttf"
    use_acknowledge_image=false
    use_confirm_image=false
    run_acknowledge=false
    r="eb" g="db" b="b2"
    bg_r="7f" bg_g="7f" bg_b="7f" bg_alpha=0 
    image_scaling=1.0

    while [ $# -gt 0 ]; do
        case $1 in
            -t|--text) text="$2"; shift ;;
            -d|--delay) delay="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -o|--okay|--acknowledge) use_acknowledge=true ;;
            *) return 1 ;;
        esac
        shift
    done

    [ "$use_acknowledge" = true ] && image=/mnt/SDCARD/Updater/imgs/acknowledge.png

    command="LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" $DISPLAY "
    command="$command""$DISPLAY_WIDTH $DISPLAY_HEIGHT $DISPLAY_ROTATION "
    command="$command""\"$image\" \"$text\" $delay $size $position $align $width $r $g $b \"$font\" $bg_r $bg_g $bg_b $bg_alpha $image_scaling"

    kill -9 $(pgrep display) 2> /dev/null

    # Execute the command in the background if delay is 0
    if [ "$delay" -eq 0 ]; then
        eval "$command" &
        [ "$use_acknowledge" = true ] && acknowledge
    else
        # Execute the command and capture its output
        eval "$command"
    fi
}

# Execute this section prior to reboot (if applicable). Skip it if reboot has already occurred.
if [ ! "$PLATFORM" = "A30" ] && [ ! -f /mnt/SDCARD/spruce/flags/reboot-update.lock ]; then
    mkdir -p /mnt/SDCARD/spruce/flags
    touch /mnt/SDCARD/spruce/flags/reboot-update.lock
    display -t "Your $PLATFORM will now reboot to allow for a safe update. Please wait!" -d 5
    log_update_message "Initial checks complete. Rebooting device to allow update to occur before mounting over important system files."
    reboot
    while true; do true; done
fi

# remove reboot-update flag after rebooting so that we don't skip the above section if a failure occurs
# further into the update script.
if [ -f /mnt/SDCARD/spruce/flags/reboot-update.lock ]; then
    log_update_message "Update continuing post-reboot!"
    rm -f /mnt/SDCARD/spruce/flags/reboot-update.lock 2>/dev/null
fi

# Start
log_update_message "Update process started"
display -t "Checking for update file..."
echo mmc0 > "$LED_PATH"/trigger &

# Create fresh updater.log and start logging
echo "Update process started" >"$LOG_LOCATION"
exec >>"$LOG_LOCATION" 2>&1

read_only_check

# Check SD Card health
TEST_FILE="/mnt/SDCARD/.sd_test_$$"
SD_ERROR=false

# Test write capability
if ! echo "test" > "$TEST_FILE" 2>/dev/null; then
    log_update_message "ERROR: Cannot write to SD card"
    display -t "SD card error: Write failed" --acknowledge
    SD_ERROR=true
else
    # Test read capability
    if ! read_test=$(cat "$TEST_FILE" 2>/dev/null) || [ "$read_test" != "test" ]; then
        log_update_message "ERROR: Cannot read from SD card or data mismatch"
        display -t "SD card error: Read failed" --acknowledge
        SD_ERROR=true
    fi
    # Clean up test file
    rm -f "$TEST_FILE"
fi

# Check filesystem space and inode usage
df_output=$(df /mnt/SDCARD 2>/dev/null)
if [ $? -ne 0 ]; then
    log_update_message "ERROR: Cannot get filesystem information"
    display -t "SD card error: Cannot check space" --acknowledge
    SD_ERROR=true
else
    # Get available space percentage (using last line in case of wrapped output)
    avail_space=$(echo "$df_output" | tail -n1 | awk '{ print $4 }')
    if [ "$avail_space" -lt 1024 ]; then  # Less than 1MB free
        log_update_message "ERROR: Insufficient space on SD card"
        display -t "SD card error: No free space" --acknowledge
        SD_ERROR=true
    fi
fi

if [ "$SD_ERROR" = true ]; then
    exit 1
else
    log_update_message "SD card is healthy"
fi

# Find update 7z file
if ! check_for_update_file; then
    display -t "No update file found" --acknowledge
    sed -i 's|"label"|"#label"|' "$APP_DIR/config.json"
    exit 1
fi

UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)

# Check battery level
log_update_message "Checking battery level"
BATTERY_CAPACITY=$(cat $BATTERY/capacity)
log_update_message "Current battery level: $BATTERY_CAPACITY%"

if [ "$BATTERY_CAPACITY" -lt 20 ] && [ "$CHARGING" -eq 0 ]; then
    log_update_message "Battery level too low for update"
    display -t "Battery too low for update.
    Please charge to at least 20% or plug in your device." --acknowledge
    exit 1
fi

boost_processing

# Extract version from update file
log_update_message "Extracting version from update file"
UPDATE_VERSION=$(echo "$UPDATE_FILE" | sed -n 's/.*spruceV\([0-9.]*\)\(-[0-9]*\)\?.7z$/\1/p')
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

#if FLAG_DIR/developer_mode* is found set a value to true
FLAG_DIR="/mnt/SDCARD/spruce/flags"
DEVELOPER_MODE=0
TESTER_MODE=0

if ls "$FLAG_DIR"/developer_mode* >/dev/null 2>&1; then
    DEVELOPER_MODE=1
fi

if ls "$FLAG_DIR"/tester_mode* >/dev/null 2>&1; then
    TESTER_MODE=1
fi

# Compare versions using awk
SKIP_VERSION_CHECK=false
BETA_UPDATE=false

if [ "$DEVELOPER_MODE" -eq 1 ] || [ "$TESTER_MODE" -eq 1 ]; then
    SKIP_VERSION_CHECK=true
    log_update_message "Version check skipped due to developer/tester mode"
fi

# Check if update file contains '-beta' flag
if echo "$UPDATE_FILE" | grep -q -- "-beta"; then
    BETA_UPDATE=true
    log_update_message "Beta update detected"
fi

log_update_message "Comparing versions: $UPDATE_VERSION vs $CURRENT_VERSION"
if [ "$SKIP_VERSION_CHECK" = true ]; then
    log_update_message "Proceeding with update (version check skipped)"
elif [ "$BETA_UPDATE" = true ]; then
    # For beta updates, only proceed if version is same or greater
    VERSION_COMPARE=$(echo "$UPDATE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print "lower"; exit} else if (a[i]>b[i]) {print "higher"; exit}} print "same"}')
    if [ "$VERSION_COMPARE" = "lower" ]; then
        log_update_message "Beta version is lower than current version, update declined"
        display -t "Current version is up to date"
        exit 0
    else
        log_update_message "Proceeding with beta update"
    fi
else
    # Regular update - only proceed if version is higher
    if [ "$(echo "$UPDATE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" = "$CURRENT_VERSION" ]; then
        log_update_message "Current version is up to date"
        if ! check_installation_validity; then
            log_update_message "Bad installation detected"
            display -t "Detected current installation is invalid.
Allowing reinstall." -d 5
        else
            display -t "Current version is up to date"
            exit 0
        fi
    else
        log_update_message "Proceeding with update"
    fi
fi

# Verify update file contents
log_update_message "Verifying update file contents"
if [ ! -f "$UPDATE_FILE" ]; then
    log_update_message "Update file not found: $UPDATE_FILE"
    display -t "Update file not found" --acknowledge
    exit 1
fi

# Verify the content of the 7z starts with /mnt/
if ! verify_7z_content "$UPDATE_FILE"; then
    display -t "Invalid update file structure, update file corrupt or not a spruce update" --acknowledge
    exit 1
fi

log_update_message "Checking file permissions"
ls -l "$UPDATE_FILE" >>"$LOG_LOCATION"
kill_network_services

# Creating a backup of current install
display -t "Creating a backup of user data and configs..."
/mnt/SDCARD/App/spruceBackup/spruceBackup.sh --silent

save_app_states

# Delete all folders and files except Updater, update zip, BIOS, Roms, Saves, miyoo/app, and miyoo/lib
PERFORM_DELETION=true
echo heartbeat > "$LED_PATH"/trigger &

if [ "$PERFORM_DELETION" = true ]; then
    log_update_message "Deleting unnecessary folders and files"
    display -t "Cleaning up your SD card..."
    cd /mnt/SDCARD
    
    # Explicitly delete .config and .tmp_update folders
    log_update_message "Deleting .config folder"
    rm -rf .config
    log_update_message "Deleting .tmp_update folder"
    rm -rf .tmp_update

    # unmount all the binds so that the deletion process can complete successfully
    log_update_message "unmounting binds"
    unmount_binds

    for item in *; do
        if [ "$item" != "Updater" ] && [ "$item" != "$(basename "$UPDATE_FILE")" ] &&
            [ "$item" != "BIOS" ] && [ "$item" != "Roms" ] && [ "$item" != "Saves" ] && [ "$item" != "Themes" ] && [ "$item" != "Persistent" ] && [ "$item" != "Collections" ]; then
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
    display -t "SD card cleaned up..." -d 2
else
    log_update_message "Skipping deletion process"
    display -t "Skipping file deletion..." -d 5
fi

# Extract update file
log_update_message "Extracting update file."
echo heartbeat > "$LED_PATH"/trigger &
cd /mnt/SDCARD
log_update_message "Current directory: $(pwd)"
log_update_message "Extracting update file: $UPDATE_FILE"

read_only_check

display -t "Applying update. This should take around 10 minutes..."

if ! 7zr x -y -scsUTF-8 "$UPDATE_FILE" >>"$LOG_LOCATION" 2>&1; then
    log_update_message "Warning: Some files may have been skipped during extraction. Check $LOG_LOCATION for details."
    display -t "Update completed with warnings. Check the update log for details." -d 5
else
    log_update_message "Extraction process completed successfully"
    display -t "Update completed" -d 5
fi

# Verify extraction success
for dir in .tmp_update spruce miyoo; do
    if [ ! -d "$dir" ]; then
        log_update_message "Extraction verification failed: $dir missing"
        display -t "Update extraction incomplete: $dir" --acknowledge
        exit 1
    fi

    if [ -z "$(ls -A "$dir")" ]; then
        log_update_message "Extraction verification failed: $dir is empty"
        display -t "Update extraction incomplete: $dir empty" --acknowledge
        exit 1
    fi
done

log_update_message "Update file extracted successfully"
display -t "Now using spruce $UPDATE_VERSION" -d 2

DELETE_UPDATE=true
if [ "$DELETE_UPDATE" = true ]; then
    log_update_message "Deleting all update files"
    # Remove all spruce update files matching the pattern
    find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" -exec rm {} \;
    log_update_message "All update files deleted"
fi

restore_app_states

# Restore backup
display -t "Restoring user data..."
/mnt/SDCARD/App/spruceRestore/spruceRestore.sh --silent

# Restore dev/test flags
if [ "$DEVELOPER_MODE" -eq 1 ]; then
    mkdir -p "$FLAG_DIR"
    touch "$FLAG_DIR/developer_mode"
    log_update_message "Restored developer mode flag"
fi

if [ "$TESTER_MODE" -eq 1 ]; then
    # Remove any developer flags when test mode was active
    rm -f "$FLAG_DIR/developer_mode"*
    touch "$FLAG_DIR/tester_mode"
    log_update_message "Restored tester mode flag"
fi

if [ "$BETA_UPDATE" -eq 1 ]; then
    touch "$FLAG_DIR/beta"
    log_update_message "Restored beta update flag"
fi

if [ "$PLATFORM" = "A30" ]; then
    display -t "Update complete. Shutting down...
    You'll need to manually power back on" -d 3
    echo 100 >/sys/devices/virtual/timed_output/vibrator/enable

else
    display -t "Update complete. Rebooting..." -d 3
    # todo: add vibration for other devices
fi

# Reboot device
killall -9 runtime.sh principal.sh MainUI PyUI

log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
if [ "$PLATFORM" = "A30" ]; then
    poweroff
else
    reboot
fi
