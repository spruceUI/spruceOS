#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR="/mnt/SDCARD/App/-Updater"
UPDATE_FILE=""
LOG_LOCATION="/mnt/SDCARD/Saves/spruce/updater.log"
FLAG_DIR="/mnt/SDCARD/spruce/flags"
LOGO="$APP_DIR/updater.png"
BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"
PERFORM_DELETION=true       ### debug variable
DELETE_UPDATE=true      ### debug variable


##### FUNCTIONS #####

# Function to log messages
log_update_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_LOCATION"
}


check_for_update_file() {
    echo "Searching for update file"
    UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)
    echo "Found update file: $UPDATE_FILE"

    if [ -z "$UPDATE_FILE" ]; then
        echo "No update file found"
        return 1
    fi
    return 0
}

check_installation_validity() {
    # Check if .tmp_update folder exists
    if [ ! -d "/mnt/SDCARD/.tmp_update" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: .tmp_update folder does not exist"
        return 1
    fi

    # Check if .tmp_update/updater file exists
    if [ ! -f "/mnt/SDCARD/.tmp_update/updater" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: .tmp_update/updater file does not exist"
        return 1
    fi

    # Both files exist, installation is valid
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation appears to be valid"
    return 0
}

kill_network_services() {
    ssh_service=$(get_ssh_service_name)

    log_update_message "Killing network services."
    killall -9 $ssh_service
    killall -9 smbd
    killall -9 sftpgo
    killall -9 syncthing
    killall -9 darkhttpd
}

verify_7z_content() {
    local archive="$1"
    local required_dirs=".tmp_update App spruce"
    local missing_dirs=""

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Verifying update file contents"

    # List contents of the archive and save to a temporary file
    local temp_list=$(mktemp)
    7zr l "$archive" >"$temp_list"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Archive contents:"
    cat "$temp_list"

    # Adding a skip for now
    #return 0

    for dir in $required_dirs; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Searching for directory: $dir"
        if grep -q "^.*D.*[[:space:]]$dir$" "$temp_list"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Found directory: $dir"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Directory not found: $dir"
            missing_dirs="$missing_dirs $dir"
        fi
    done

    rm -f "$temp_list"

    if [ -n "$missing_dirs" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Required director(ies)$missing_dirs not found in 7z file"
        return 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - All required directories found in 7z file"
    return 0
}

unmount_binds() {
    PRESERVE="/mnt/sdcard /userdata /mnt/SDCARD /mnt/sdcard/mmcblk1p1"
    echo "[INFO] Scanning /proc/self/mountinfo for bind mounts from $SD_DEV..."
    cat /proc/self/mountinfo | while read -r line; do
    # Extract everything after the last " - ", then get the device (6th field overall)
    DEVICE=$(echo "$line" | awk -F ' - ' '{print $2}' | awk '{print $2}')
    TARGET=$(echo "$line" | awk '{print $5}')

    if [ "$DEVICE" = "$SD_DEV" ]; then
        echo "[FOUND] $TARGET mounted from $DEVICE"

        SKIP=0
        for p in $PRESERVE; do
        if [ "$TARGET" = "$p" ]; then
            SKIP=1
            echo "[SKIP] Preserved target: $TARGET"
            break
        fi
        done

        if [ "$SKIP" -eq 0 ]; then
        echo "[UMOUNT] Attempting to unmount $TARGET"
        umount "$TARGET" || echo "[ERROR] Failed to unmount $TARGET"
        fi
    fi
    done
}


##### MAIN EXECUTION #####

start_pyui_message_writer

# twinkle them lights
rgb_led lrm12 breathe 0000FF 2000 "-1" mmc0

# Create fresh updater.log and start logging
echo "Update process started" >"$LOG_LOCATION"
exec >>"$LOG_LOCATION" 2>&1

display_image_and_text "$LOGO" 35 25 "Checking for update file..." 75

read_only_check

# debug info
echo "Update is being performed on a $PLATFORM."
echo "Device firmware is version: $(cat /etc/version)"
echo "Currently running processes:"
ps
echo "Current mounts:"
mount
echo "SD Card root contents:"
ls -Al "$SD_MOUNTPOINT"
echo "PATH: $PATH"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# Check SD Card health
TEST_FILE="/mnt/SDCARD/.sd_test_$$"
SD_ERROR=false

# Test write capability
if ! echo "test" > "$TEST_FILE" 2>/dev/null; then
    log_update_message "ERROR: Cannot write to SD card"
    display_image_and_text "$BAD_IMG" 35 25 "SD card error: Write failed" 75
    SD_ERROR=true
else
    # Test read capability
    if ! read_test=$(cat "$TEST_FILE" 2>/dev/null) || [ "$read_test" != "test" ]; then
        log_update_message "ERROR: Cannot read from SD card or data mismatch"
        display_image_and_text "$BAD_IMG" 35 25 "SD card error: Read failed" 75
        SD_ERROR=true
    fi
    # Clean up test file
    rm -f "$TEST_FILE"
fi

# Check filesystem space and inode usage
df_output=$(df /mnt/SDCARD 2>/dev/null)
if [ $? -ne 0 ]; then
    log_update_message "ERROR: Cannot get filesystem information"
    display_image_and_text "$BAD_IMG" 35 25 "SD card error: Cannot check space" 75
    SD_ERROR=true
else
    # Get available space percentage (using last line in case of wrapped output)
    avail_space=$(echo "$df_output" | tail -n1 | awk '{ print $4 }')
    if [ "$avail_space" -lt 1024 ]; then  # Less than 1MB free
        log_update_message "ERROR: Insufficient space on SD card"
        display_image_and_text "$BAD_IMG" 35 25 "SD card error: No free space" 75
        SD_ERROR=true
    fi
fi

if [ "$SD_ERROR" = true ]; then
    sleep 5
    exit 1
else
    log_update_message "SD card is healthy."
fi

# Find update 7z file; exit and hide updater app if none exists
if ! check_for_update_file; then
    display_image_and_text "$BAD_IMG" 35 25 "No update file found" 75
    sed -i 's|"label"|"#label"|' "$APP_DIR/config.json"
    sleep 5
    exit 1
fi
UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)

# Check battery level
log_update_message "Checking battery level"
BATTERY_CAPACITY="$(device_get_battery_percent)"
CHARGING="$(device_get_charging_status)"
log_update_message "Current battery level: $BATTERY_CAPACITY%"

if [ "$BATTERY_CAPACITY" -lt 20 ] && [ "$CHARGING" = "Discharging" ]; then
    log_update_message "Battery level too low for update"
    display_image_and_text "$BAD_IMG" 35 25 "Battery too low for update.\nPlease charge to at least 20% or plug in your device, then try again." 75
    sleep 5
    exit 1
fi

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

DEVELOPER_MODE=0
TESTER_MODE=0
if flag_check "developer_mode"; then
    DEVELOPER_MODE=1
fi
if flag_check "tester_mode"; then
    TESTER_MODE=1
fi

# Compare versions using awk
SKIP_VERSION_CHECK="$(get_config_value '.menuOptions."Network Settings".otaskipVersionCheck.selected' "True")"
BETA_UPDATE=false

if [ "$DEVELOPER_MODE" -eq 1 ] || [ "$TESTER_MODE" -eq 1 ]; then
    SKIP_VERSION_CHECK="True"
    log_update_message "Version check skipped due to developer/tester mode"
fi

# Check if update file contains '-beta' flag
if echo "$UPDATE_FILE" | grep -q -- "-beta"; then
    BETA_UPDATE=true
    log_update_message "Beta update detected"
fi

log_update_message "Comparing versions: $UPDATE_VERSION vs $CURRENT_VERSION"
if [ "$SKIP_VERSION_CHECK" = "True" ]; then
    log_update_message "Proceeding with update (version check skipped)"
elif [ "$BETA_UPDATE" = true ]; then
    # For beta updates, only proceed if version is same or greater
    VERSION_COMPARE=$(echo "$UPDATE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print "lower"; exit} else if (a[i]>b[i]) {print "higher"; exit}} print "same"}')
    if [ "$VERSION_COMPARE" = "lower" ]; then
        log_update_message "Beta version is lower than current version, update declined"
        display_image_and_text "$LOGO" 35 25 "Current version is up to date." 75
        sleep 5
        exit 0
    else
        log_update_message "Proceeding with beta update"
    fi
else    ### Regular update - only proceed if version is higher
    if [ "$(echo "$UPDATE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" = "$CURRENT_VERSION" ]; then
        log_update_message "Current version is up to date"
        if ! check_installation_validity; then
            log_update_message "Bad installation detected"
            display_image_and_text "$LOGO" 35 25 "Detected current installation is invalid. Allowing reinstall." 75
            sleep 5
        else
            display_image_and_text "$LOGO" 35 25 "Current version is up to date." 75
            sleep 5
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
    display_image_and_text "$BAD_IMG" 35 25 "Update file not found" 75
    sleep 5
    exit 1
fi

# Verify the content of the 7z starts with /mnt/
if ! verify_7z_content "$UPDATE_FILE"; then
    display_image_and_text "$BAD_IMG" 35 25 "Invalid update file structure. Update file corrupt or not a spruce update." 75
    sleep 5
    exit 1
fi

log_update_message "Checking file permissions"
ls -l "$UPDATE_FILE" >>"$LOG_LOCATION"
kill_network_services

# Creating a backup of current install
/mnt/SDCARD/App/spruceBackup/spruceBackup.sh

[ "$LED_PATH" != "not applicable" ] && echo heartbeat > "$LED_PATH"/trigger

# Delete all folders and files except the update zip, BIOS, Roms, Saves, Persistent, Themes, and Collections
if [ "$PERFORM_DELETION" = true ]; then
    log_update_message "Deleting unnecessary folders and files"
    display_image_and_text "$LOGO" 35 25 "Cleaning up your SD card..." 75

    DELETION_SCRIPT="/mnt/SDCARD/App/-Updater/delete_files.sh"
    chmod a+x "$DELETION_SCRIPT"
    if [ -x "$DELETION_SCRIPT" ]; then
        "$DELETION_SCRIPT"
        rc=$?
        if [ $rc -ne 0 ]; then
            log_update_message "Deletion script failed with code $rc"
            display_image_and_text "$LOGO" 35 25 "Cleanup failed!" 75
            sleep 5
        else
            display_image_and_text "$LOGO" 35 25 "SD card cleaned up..." 75
            sleep 2
        fi
    else
        log_update_message "Deletion script missing or not executable"
        display_image_and_text "$LOGO" 35 25 "Cleanup skipped!" 75
        sleep 5
    fi
else
    log_update_message "Skipping deletion process"
    display_image_and_text "$LOGO" 35 25 "Skipping file deletion..." 75
    sleep 5
fi

# Extract update file
log_update_message "Extracting update file."
cd /mnt/SDCARD
log_update_message "Current directory: $(pwd)"
log_update_message "Extracting update file: $UPDATE_FILE"

read_only_check

display_image_and_text "$LOGO" 35 25 "Applying update. This should take around 10 minutes..." 75

# -----------------------------
# 1️⃣ Count total files in archive
# -----------------------------
TOTAL_FILES=$(7zr l -scsUTF-8 "$UPDATE_FILE" |
awk '$1 ~ /^[0-9][0-9][0-9][0-9]-/ { count++ } END { print count }')
[ "$TOTAL_FILES" -eq 0 ] && TOTAL_FILES=1

# -----------------------------
# 2️⃣ Initialize counters
# -----------------------------
FILE_COUNT=0
PERCENT_COMPLETE=0
THROTTLE=10  # update display every 10 files

# -----------------------------
# 3️⃣ Extract and update UI
# -----------------------------
7zr x -y -scsUTF-8 -bb1 "$UPDATE_FILE" 2>>"$LOG_LOCATION" |
while read -r line || [ -n "$line" ]; do
    # Remove leading dash/spaces
    FILE=$(echo "$line" | sed 's/^[-[:space:]]*//')
    [ -z "$FILE" ] && continue

    FILE_COUNT=$((FILE_COUNT + 1))
    PERCENT_COMPLETE=$((FILE_COUNT * 100 / TOTAL_FILES))

    # Throttle UI updates for performance
    if [ $((FILE_COUNT % THROTTLE)) -eq 0 ] || [ "$FILE_COUNT" -eq "$TOTAL_FILES" ]; then
        display_text_with_percentage_bar \
            "$FILE" \
            "$PERCENT_COMPLETE" \
            "$FILE_COUNT / $TOTAL_FILES files"
    fi
done

# -----------------------------
# 4️⃣ Capture exit code
# -----------------------------
RET=$?


# Success / warning logic
if [ "$RET" -ne 0 ]; then
    log_update_message "Warning: Some files may have been skipped during extraction. Check $LOG_LOCATION for details."
    display_image_and_text "$LOGO" 35 25 \
        "Update completed with warnings. Check the update log for details." 75
else
    log_update_message "Extraction process completed successfully"
    display_image_and_text "$LOGO" 35 25 "Update completed!" 75
fi


sleep 5

# Verify extraction success
for dir in .tmp_update spruce miyoo miyoo355 trimui; do
    if [ ! -d "$dir" ]; then
        log_update_message "Extraction verification failed: $dir missing"
        display_image_and_text "$BAD_IMG" 35 25 "Update extraction incomplete: $dir" 75
        sleep 5
        exit 1
    fi

    if [ -z "$(ls -A "$dir")" ]; then
        log_update_message "Extraction verification failed: $dir is empty"
        display_image_and_text "$BAD_IMG" 35 25 "Update extraction incomplete: $dir empty" 75
        sleep 5
        exit 1
    fi
done

log_update_message "Update file extracted successfully"
display_image_and_text "$LOGO" 35 25 "Now using spruce $UPDATE_VERSION" 75
sleep 5

if [ "$DELETE_UPDATE" = true ]; then
    log_update_message "Deleting all update files"
    # Remove all spruce update files matching the pattern
    find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" -exec rm {} \;
    log_update_message "All update files deleted"
fi

# Restore backup
/mnt/SDCARD/App/spruceRestore/spruceRestore.sh

# Restore dev/test flags
if [ "$DEVELOPER_MODE" -eq 1 ]; then
    mkdir -p "$FLAG_DIR"
    flag_add "developer_mode"
    log_update_message "Restored developer mode flag"
fi

if [ "$TESTER_MODE" -eq 1 ]; then
    # Remove any developer flags when test mode was active
    flag_remove "developer_mode"
    flag_add "tester_mode"
    log_update_message "Restored tester mode flag"
fi

if [ "$BETA_UPDATE" = true ]; then
    touch "$FLAG_DIR/beta"
    log_update_message "Restored beta update flag"
fi

if [ "$PLATFORM" = "A30" ]; then
    display_image_and_text "$LOGO" 35 25 "Update complete. Shutting down... You will need to manually power back on." 75
else
    display_image_and_text "$LOGO" 35 25 "Update complete. Rebooting..." 75
fi

sleep 5
vibrate &

# Reboot device
killall -9 runtime.sh principal.sh MainUI

log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
if [ "$PLATFORM" = "A30" ]; then
    poweroff
else
    reboot
fi
