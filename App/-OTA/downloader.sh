#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/-OTA/downloaderFunctions.sh
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

SD_CARD="/mnt/SDCARD"

IMAGE_PATH="$SD_CARD/spruce/imgs/update.png"

OTA_URL="https://spruceui.github.io/OTA/spruce"
OTA_URL_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceui.github.io/refs/heads/main/OTA/spruce"
OTA_URL_BACKUP_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceSource/refs/heads/main/OTA/spruce"
TMP_DIR="$SD_CARD/App/-OTA/tmp"

BATTERY_CAPACITY="$(cat $BATTERY/capacity)"
CHARGING="$(cat $BATTERY/online)"

display --icon "$IMAGE_PATH" -t "Checking for updates..."

VERSION="$(cat /usr/miyoo/version)"
if [ "$VERSION" -lt 20240713100458 ]; then
    sed -i 's|"#label":|"label":|' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
    display --icon "$IMAGE_PATH" -t "Firmware version is too old. Please update your firmware to 20240713100458 or later." --okay
    exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Check for Wi-Fi and active connection
wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$SYSTEM_JSON")
if [ "$wifi_enabled" -eq 0 ] || ! ping -c 3 spruceui.github.io >/dev/null 2>&1; then
    log_message "OTA: No active network connection, exiting."
    display --icon "$IMAGE_PATH" -t "No active network connection detected, please turn on WiFi and try again." --okay
    rm -rf "$TMP_DIR"
    exit 1
fi

CURRENT_VERSION=$(get_version)

read_only_check

# Try primary and backup URLs
if ! download_release_info "$OTA_URL" "$TMP_DIR/spruce" "$TMP_DIR"; then
    log_message "OTA: Primary URL failed, trying backup URL"
    if ! download_release_info "$OTA_URL_BACKUP" "$TMP_DIR/spruce" "$TMP_DIR"; then
        log_message "OTA: First backup URL failed, trying second backup URL"
        if ! download_release_info "$OTA_URL_BACKUP_BACKUP" "$TMP_DIR/spruce" "$TMP_DIR"; then
            display --icon "$IMAGE_PATH" -t "Update check failed, could not get valid update info. Please try again later." --okay
            rm -rf "$TMP_DIR"
            exit 1
        fi
    fi
fi

# If we get here, we have valid content in $TMP_DIR/spruce

# Extract version info from downloaded file
RELEASE_VERSION=$(sed -n 's/RELEASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_CHECKSUM=$(sed -n 's/RELEASE_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_LINK=$(sed -n 's/RELEASE_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_SIZE=$(sed -n 's/RELEASE_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_INFO=$(sed -n 's/RELEASE_INFO=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

# Extract nightly info
NIGHTLY_VERSION=$(sed -n 's/NIGHTLY_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_CHECKSUM=$(sed -n 's/NIGHTLY_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_LINK=$(sed -n 's/NIGHTLY_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_SIZE=$(sed -n 's/NIGHTLY_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_INFO=$(sed -n 's/NIGHTLY_INFO=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

# Extract beta info
BETA_VERSION=$(sed -n 's/BETA_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
BETA_CHECKSUM=$(sed -n 's/BETA_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
BETA_LINK=$(sed -n 's/BETA_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
BETA_SIZE=$(sed -n 's/BETA_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
BETA_INFO=$(sed -n 's/BETA_INFO=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

# Function to offer version choice
offer_version() {
    local prompt="$1"
    local version1="$2"
    local version1_name="$3"
    local version2="$4"
    local version2_name="$5"
    
    display --icon "$IMAGE_PATH" -t "$prompt
$version1_name: $version1
$version2_name: $version2" -p 220 --confirm
    confirm
    return $?
}

# Set default target to release
TARGET_VERSION="$RELEASE_VERSION"
TARGET_CHECKSUM="$RELEASE_CHECKSUM"
TARGET_LINK="$RELEASE_LINK"
TARGET_SIZE="$RELEASE_SIZE"
TARGET_INFO="$RELEASE_INFO"

# Function to set target version
set_target() {
    local version="$1"
    local checksum="$2"
    local link="$3"
    local size="$4"
    local info="$5"
    
    TARGET_VERSION="$version"
    TARGET_CHECKSUM="$checksum"
    TARGET_LINK="$link"
    TARGET_SIZE="$size"
    TARGET_INFO="$info"
}

# Handle version selection based on flags
if flag_check "developer_mode"; then
    # Developer mode: offer nightly -> beta -> release
    if offer_version "Developer mode detected. Would you like to use the latest nightly build?" "$NIGHTLY_VERSION" "Latest nightly" "$RELEASE_VERSION" "Public release"; then
        set_target "$NIGHTLY_VERSION" "$NIGHTLY_CHECKSUM" "$NIGHTLY_LINK" "$NIGHTLY_SIZE" "$NIGHTLY_INFO"
    elif [ -n "$BETA_VERSION" ]; then
        if offer_version "Would you like to use the beta build instead?" "$BETA_VERSION" "Beta version" "$RELEASE_VERSION" "Public release"; then
            set_target "$BETA_VERSION" "$BETA_CHECKSUM" "$BETA_LINK" "$BETA_SIZE" "$BETA_INFO"
        fi
    fi
elif flag_check "beta"; then
    # Beta mode: offer beta (if exists) -> release
    if [ -n "$BETA_VERSION" ]; then
        if offer_version "Beta mode detected. Would you like to use the beta build?" "$BETA_VERSION" "Beta version" "$RELEASE_VERSION" "Public release"; then
            set_target "$BETA_VERSION" "$BETA_CHECKSUM" "$BETA_LINK" "$BETA_SIZE" "$BETA_INFO"
        fi
    fi
elif flag_check "tester_mode"; then
    # Tester mode: offer beta (if exists) -> nightly -> release
    if [ -n "$BETA_VERSION" ]; then
        if offer_version "Tester mode detected. Would you like to use the beta build?" "$BETA_VERSION" "Beta version" "$RELEASE_VERSION" "Public release"; then
            set_target "$BETA_VERSION" "$BETA_CHECKSUM" "$BETA_LINK" "$BETA_SIZE" "$BETA_INFO"
        elif offer_version "Would you like to use the latest nightly instead?" "$NIGHTLY_VERSION" "Latest nightly" "$RELEASE_VERSION" "Public release"; then
            set_target "$NIGHTLY_VERSION" "$NIGHTLY_CHECKSUM" "$NIGHTLY_LINK" "$NIGHTLY_SIZE" "$NIGHTLY_INFO"
        fi
    else
        if offer_version "Tester mode detected. Would you like to use the latest nightly build?" "$NIGHTLY_VERSION" "Latest nightly" "$RELEASE_VERSION" "Public release"; then
            set_target "$NIGHTLY_VERSION" "$NIGHTLY_CHECKSUM" "$NIGHTLY_LINK" "$NIGHTLY_SIZE" "$NIGHTLY_INFO"
        fi
    fi
fi

SKIP_VERSION_CHECK="$(get_config_value '.menuOptions."Network Settings".otaskipVersionCheck.selected' "True")"
# Set SKIP_VERSION_CHECK to True if developer mode or tester mode is enabled
if flag_check "developer_mode" || flag_check "tester_mode" || flag_check "beta"; then
    SKIP_VERSION_CHECK="True"
fi

# Fallback to default release URL if INFO is not available
if [ -z "$TARGET_INFO" ]; then
    TARGET_INFO="https://github.com/spruceUI/spruceOS/releases/latest"
fi

if [ -z "$TARGET_VERSION" ] || [ -z "$TARGET_CHECKSUM" ] || [ -z "$TARGET_LINK" ] || [ -z "$TARGET_SIZE" ]; then
    log_message "OTA: Invalid release info file format
    Target version: $TARGET_VERSION
    Target checksum: $TARGET_CHECKSUM
    Target link: $TARGET_LINK
    Target size: $TARGET_SIZE"
    display --icon "$IMAGE_PATH" -t "Update check failed: Invalid release info" --okay
    rm -rf "$TMP_DIR"
    exit 1
fi

# Compare versions
log_update_message "Comparing versions: $TARGET_VERSION vs $CURRENT_VERSION"
if [ "$SKIP_VERSION_CHECK" = "True" ] || [ "$(echo "$TARGET_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$CURRENT_VERSION" ]; then
    log_update_message "Proceeding with update"
else
    log_update_message "Current version is up to date"
    display --icon "$IMAGE_PATH" -t "System is up to date
Installed version: $CURRENT_VERSION
Latest version: $TARGET_VERSION" --okay
    rm -rf "$TMP_DIR"
    exit 0
fi

if [ "$BATTERY_CAPACITY" -lt 20 ] && [ "$CHARGING" -eq 0 ]; then
    log_message "OTA: Battery level too low for update"
    display --icon "$IMAGE_PATH" -t "Battery too low for update.
You can still download the update, but you will need to charge your device to at least 20% or plug it in.
Afterwards you may use the EZ Updater app to install the update." -p 220 --okay
log_message "OTA: Battery level: $BATTERY_CAPACITY%
Charging: $CHARGING"
fi


display -t "Scan QR code for release notes.
Newer version available: $TARGET_VERSION
Download and install?" --confirm --qr "$TARGET_INFO"
if confirm 300; then
    log_message "OTA: User confirmed"
else
    log_message "OTA: User did not confirm"
    display --icon "$IMAGE_PATH" -t "Update cancelled" -d 3
    rm -rf "$TMP_DIR"
    exit 0
fi

# Extract filename from TARGET_LINK
FILENAME=$(echo "$TARGET_LINK" | sed 's/.*\///')

# Function to verify checksum and handle file cleanup
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local downloaded_checksum

    downloaded_checksum=$(md5sum "$file" | cut -d' ' -f1)

    if [ "$(printf '%s' "$downloaded_checksum")" = "$(printf '%s' "$expected_checksum")" ]; then
        return 0 # Success
    else
        log_message "OTA: Checksum verification failed, received: $downloaded_checksum, expected: $expected_checksum"
        rm -f "$file"
        return 1 # Failure
    fi
}

# Check if update file already exists
if [ -f "$SD_CARD/$FILENAME" ]; then
    display --icon "$IMAGE_PATH" -t "Update file already exists. Verifying..."
    log_message "OTA: Update file already exists"
    if verify_checksum "$SD_CARD/$FILENAME" "$TARGET_CHECKSUM"; then
        display --icon "$IMAGE_PATH" -t "Valid update file already exists. Download again anyways?" --confirm
        if ! confirm; then
            log_message "OTA: User chose to use existing file"
            rm -rf "$TMP_DIR"
            goto_install=true
        else
            rm -rf "$SD_CARD/$FILENAME"
        fi
    else
        display --icon "$IMAGE_PATH" -t "Existing update file isn't valid. Will download fresh copy." -d 3
    fi
fi

if [ "$goto_install" != "true" ]; then
    # Check free disk space
    sdcard_mountpoint="$(mount | grep -m 1 "$SD_CARD" | awk '{print $1}')"
    sdcard_freespace="$(df -m "$sdcard_mountpoint" | awk 'NR==2{print $4}')"
    min_install_space=$(((TARGET_SIZE * 2) + 128))
    if [ "$free_space" -lt "$min_install_space" ]; then
        log_message "OTA: Not enough free space on SD card (at least ${min_install_space}MB should be free)"
        display --icon "$IMAGE_PATH" -t "Insufficient space on SD card. At least ${min_install_space}MB of space should be free." --okay
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Download update file
    display --icon "$IMAGE_PATH" -t "Downloading update..."
    download_progress "$SD_CARD/$FILENAME" "$TARGET_SIZE" &
    download_pid=$! # Store the PID of the background process

    if ! curl -k -L -o "$SD_CARD/$FILENAME" "$TARGET_LINK" 2>"$TMP_DIR/curl_error"; then
        kill $download_pid
        error_msg=$(cat "$TMP_DIR/curl_error")
        log_message "OTA: Failed to download update file - Error: $error_msg"
        display --icon "$IMAGE_PATH" -t "Update download failed" --okay
        rm -rf "$TMP_DIR"
        exit 1
    fi

    kill $download_pid # Kill the progress display after successful download

    # Verify checksum
    display --icon "$IMAGE_PATH" -t "Download complete! Verifying..."
    if ! verify_checksum "$SD_CARD/$FILENAME" "$TARGET_CHECKSUM"; then
        display --icon "$IMAGE_PATH" -t "File downloaded but not verified. Try again..." --okay
        rm -rf "$TMP_DIR"
        exit 1
    fi
    vibrate &
fi

rm -rf "$TMP_DIR"
# Show updater app
sed -i 's|"#label"|"label"|' /mnt/SDCARD/App/-Updater/config.json"

# Check battery level before asking to update
if [ $BATTERY_CAPACITY -lt 20 ] && [ $CHARGING -eq 0 ]; then
    log_message "OTA: Battery level too low for update"
    display --icon "$IMAGE_PATH" -t "Battery too low for update.
Please charge to at least 30% or plug in your device. You can run the EZ Updater app to install the already downloaded update." -p 220 --okay
    exit 0
fi

# Update script call
display --icon "$IMAGE_PATH" -t "Download successful! Install now?" --confirm
if confirm 30 0; then
    log_message "OTA: Update confirmed"
    /mnt/SDCARD/Updater/updater.sh
else
    log_message "OTA: Update declined"
    exit 0
fi
