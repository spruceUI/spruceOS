#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/OTA/downloaderFunctions.sh

SD_CARD="/mnt/SDCARD"

IMAGE_PATH="$SD_CARD/Updater/imgs/updater.png"

OTA_URL="https://spruceui.github.io/OTA/spruce"
TMP_DIR="$SD_CARD/App/OTA/tmp"

display --icon "$IMAGE_PATH" -t "Checking for updates..."

mkdir -p "$TMP_DIR"

# Check for Wi-Fi and active connection
wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$system_config_file")
if [ "$wifi_enabled" -eq 0 ] || ! ping -c 3 spruceui.github.io  > /dev/null 2>&1; then
    log_message "OTA: No active network connection, exiting."
	display --icon "$IMAGE_PATH" -t "No active network connection detected, please turn on WiFi and try again." --okay
    rm -rf "$TMP_DIR"
    exit 1
fi

CURRENT_VERSION=$(get_version)

read_only_check

# Download and parse the release info file
if ! curl -s -o "$TMP_DIR/spruce" "$OTA_URL"; then
    log_message "OTA: Failed to download release info"
    display --icon "$IMAGE_PATH" -t "Update check failed, please try again." --okay
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract version info from downloaded file
RELEASE_VERSION=$(sed -n 's/RELEASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_CHECKSUM=$(sed -n 's/RELEASE_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_LINK=$(sed -n 's/RELEASE_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_SIZE=$(sed -n 's/RELEASE_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

if [ -z "$RELEASE_VERSION" ] || [ -z "$RELEASE_CHECKSUM" ] || [ -z "$RELEASE_LINK" ] || [ -z "$RELEASE_SIZE" ]; then
    log_message "OTA: Invalid release info file format"
    display --icon "$IMAGE_PATH" -t "Update check failed: Invalid release info" --okay
    rm -rf "$TMP_DIR"
    exit 1
fi

# Compare versions
UPDATE_SAME_VERSION=true
log_update_message "Comparing versions: $RELEASE_VERSION vs $CURRENT_VERSION"
if [ "$UPDATE_SAME_VERSION" = true ] || [ "$(echo "$RELEASE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$CURRENT_VERSION" ]; then
    log_update_message "Proceeding with update"
else
    log_update_message "Current version is up to date"
    display --icon "$IMAGE_PATH" -t "System is up to date
Current version: $CURRENT_VERSION
Latest version: $RELEASE_VERSION" --okay
    rm -rf "$TMP_DIR"
    exit 0
fi

display --icon "$IMAGE_PATH" -t "Newer version available: $RELEASE_VERSION
Download and install?" --confirm
if confirm; then
    log_message "OTA: User confirmed"
else
    log_message "OTA: User did not confirm"
    display -t "Update cancelled" -d 3
    rm -rf "$TMP_DIR"
    exit 0
fi

# Extract filename from RELEASE_LINK
FILENAME=$(echo "$RELEASE_LINK" | sed 's/.*\///')

# Function to verify checksum and handle file cleanup
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local downloaded_checksum

    downloaded_checksum=$(md5sum "$file" | cut -d' ' -f1)
    
    if [ "$(printf '%s' "$downloaded_checksum")" = "$(printf '%s' "$expected_checksum")" ]; then
        return 0  # Success
    else
        log_message "OTA: Checksum verification failed, received: $downloaded_checksum, expected: $expected_checksum"
        rm -f "$file"
        return 1  # Failure
    fi
}

# Check if update file already exists
if [ -f "$SD_CARD/$FILENAME" ]; then
    log_message "OTA: Update file already exists"
    if verify_checksum "$SD_CARD/$FILENAME" "$RELEASE_CHECKSUM"; then
        display --icon "$IMAGE_PATH" -t "Valid update file already exists. Download again anyways?" --confirm
        if ! confirm; then
            log_message "OTA: User chose to use existing file"
            rm -rf "$TMP_DIR"
            goto_install=true
        fi
    else
        display --icon "$IMAGE_PATH" -t "Existing update file is corrupt. Will download fresh copy." -d 3
    fi
fi


if [ "$goto_install" != "true" ]; then
    # Check free disk space
    sdcard_mountpoint="$(mount | grep -m 1 "$SD_CARD" | awk '{print $1}')"
    sdcard_freespace="$(df -m "$sdcard_mountpoint" | awk 'NR==2{print $4}')"
    min_install_space=$(((RELEASE_SIZE * 2) + 128))
    if [ "$free_space" -lt "$min_install_space" ]; then
        log_message "OTA: Not enough free space on SD card (at least ${min_install_space}MB should be free)"
        display --icon "$IMAGE_PATH" -t "Insufficient space on SD card. At least ${min_install_space}MB of space should be free." --okay
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Download update file
    display --icon "$IMAGE_PATH" -t "Downloading update..."
    download_progress "$SD_CARD/$FILENAME" "$RELEASE_SIZE" &
    download_pid=$!  # Store the PID of the background process

    if ! curl -L -o "$SD_CARD/$FILENAME" "$RELEASE_LINK"; then
        kill $download_pid  # Kill the progress display if download fails
        log_message "OTA: Failed to download update file"
        display --icon "$IMAGE_PATH" -t "Update download failed" --okay
        rm -rf "$TMP_DIR"
        exit 1
    fi

    kill $download_pid  # Kill the progress display after successful download

    # Verify checksum
    display --icon "$IMAGE_PATH" -t "Download complete! Verifying..." -d 3
    if ! verify_checksum "$SD_CARD/$FILENAME" "$RELEASE_CHECKSUM"; then
        display --icon "$IMAGE_PATH" -t "File downloaded but not verified. Try again..." --okay
        rm -rf "$TMP_DIR"
        exit 1
    fi
    vibrate &
fi

rm -rf "$TMP_DIR"
# Show updater app
/mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh show "$SD_CARD/App/-Updater/config.json"

# Update script call
display --icon "$IMAGE_PATH" -t "Download successful! Install now?" --confirm
if confirm; then
    log_message "OTA: User confirmed"
    /mnt/SDCARD/Updater/updater.sh
else
    log_message "OTA: User did not confirm"
    exit 0
fi
