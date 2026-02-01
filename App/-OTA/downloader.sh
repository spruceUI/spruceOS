#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/update.png"
BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"

OTA_URL="https://spruceui.github.io/OTA/spruce"
OTA_URL_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceui.github.io/refs/heads/main/OTA/spruce"
OTA_URL_BACKUP_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceSource/refs/heads/main/OTA/spruce"
TMP_DIR="/mnt/SDCARD/App/-OTA/tmp"

##### FUNCTIONS #####

is_wifi_connected() {
    if ping -c 3 -W 2 spruceui.github.io > /dev/null 2>&1; then
        log_message "GitHub ping successful; device is online."
        return 0
    else
        display_image_and_text "$BAD_IMG" 35 20 "GitHub ping failed; device is offline. Aborting." 75
        return 1
    fi
}

download_release_info() {
    local url="$1"
    local output_file="$2"
    local tmp_dir="$3"
    
    # Try to download the file
    if ! curl -k -S -s -f -o "$output_file" "$url" 2>"$tmp_dir/curl_error"; then
        error_msg=$(cat "$tmp_dir/curl_error")
        log_message "OTA: Failed to download from $url - Error: $error_msg"
        return 1
    fi
    
    # Verify we got valid content
    if ! grep -q "RELEASE_VERSION=" "$output_file"; then
        log_message "OTA: Invalid or empty release info file from $url"
        return 1
    fi
    
    return 0
}

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

##### MAIN EXECUTION #####

start_pyui_message_writer
display_image_and_text "$IMAGE_PATH" 35 25 "Checking for updates..." 75

# twinkle them lights
rgb_led lrm12 blink2 0000FF 1500 "-1" mmc0

# Fix the wifi first if using an A30 with outdated firmware
if [ "$PLATFORM" = "A30" ]; then
    VERSION="$(cat /usr/miyoo/version)"
    if [ "$VERSION" -lt 20240713100458 ]; then
        sed -i 's|"#label":|"label":|' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
        display_image_and_text "$IMAGE_PATH" 35 25 "Firmware version is too old. Please update your firmware using the Firmware Updater app, then try again." 75
        sleep 5
        exit 1
    fi
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Check for Wi-Fi and active connection
if ! is_wifi_connected; then sleep 3; exit 1; fi

CURRENT_VERSION=$(get_version)  # this comes from helperFunctions.sh
read_only_check                 # this too is from helperFunctions.sh

# Try primary and backup URLs
if ! download_release_info "$OTA_URL" "$TMP_DIR/spruce" "$TMP_DIR"; then
    log_message "OTA: Primary URL failed; trying backup URL"
    if ! download_release_info "$OTA_URL_BACKUP" "$TMP_DIR/spruce" "$TMP_DIR"; then
        log_message "OTA: First backup URL failed; trying second backup URL"
        if ! download_release_info "$OTA_URL_BACKUP_BACKUP" "$TMP_DIR/spruce" "$TMP_DIR"; then
            display_image_and_text "$IMAGE_PATH" 35 25 "Update check failed; could not get valid update info. Please try again later." 75
            sleep 5
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

# Set default target to release
TARGET_VERSION="$RELEASE_VERSION"
TARGET_CHECKSUM="$RELEASE_CHECKSUM"
TARGET_LINK="$RELEASE_LINK"
TARGET_SIZE="$RELEASE_SIZE"
TARGET_INFO="$RELEASE_INFO"

# Handle version selection based on flags
if flag_check "developer_mode"; then
    # Developer mode: offer nightly -> beta -> release
    display_image_and_text "$IMAGE_PATH" 35 25 "Developer mode detected. Press A to update to nightly build $NIGHTLY_VERSION." 75
    if confirm 30 0; then
        set_target "$NIGHTLY_VERSION" "$NIGHTLY_CHECKSUM" "$NIGHTLY_LINK" "$NIGHTLY_SIZE" "$NIGHTLY_INFO"
    elif [ -n "$BETA_VERSION" ]; then
        display_image_and_text "$IMAGE_PATH" 35 25 "Would you like to use the current beta version instead? Press A to update to $BETA_VERSION." 75
        if confirm 30 1; then
            set_target "$BETA_VERSION" "$BETA_CHECKSUM" "$BETA_LINK" "$BETA_SIZE" "$BETA_INFO"
        fi
    fi
elif flag_check "beta"; then
    # Beta mode: offer beta (if exists) -> release
    if [ -n "$BETA_VERSION" ]; then
        display_image_and_text "$IMAGE_PATH" 35 25 "Beta mode detected. Would you like to use the beta build? Press A to update to $BETA_VERSION." 75
        if confirm 30 0; then
            set_target "$BETA_VERSION" "$BETA_CHECKSUM" "$BETA_LINK" "$BETA_SIZE" "$BETA_INFO"
        fi
    fi
elif flag_check "tester_mode"; then
    # Tester mode: offer beta (if exists) -> nightly -> release
    if [ -n "$BETA_VERSION" ]; then
        display_image_and_text "$IMAGE_PATH" 35 25 "Tester mode detected. Would you like to use the beta build? Press A to update to $BETA_VERSION." 75
        if confirm 30 0; then
            set_target "$BETA_VERSION" "$BETA_CHECKSUM" "$BETA_LINK" "$BETA_SIZE" "$BETA_INFO"
        else
            display_image_and_text "$IMAGE_PATH" 35 25 "Would you like to use the nightly release instead? Press A to update to nightly build $NIGHTLY_VERSION." 75
            if confirm 30 0; then
                set_target "$NIGHTLY_VERSION" "$NIGHTLY_CHECKSUM" "$NIGHTLY_LINK" "$NIGHTLY_SIZE" "$NIGHTLY_INFO"
            fi
        fi
    else
        display_image_and_text "$IMAGE_PATH" 35 25 "Tester mode detected. Press A to update to nightly build $NIGHTLY_VERSION." 75
        if confirm; then
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
    display_image_and_text "$BAD_IMG" 35 20 "Update check failed: Invalid release info." 75
    sleep 5
    rm -rf "$TMP_DIR"
    exit 1
fi

# Compare versions
log_message "Comparing versions: $TARGET_VERSION vs $CURRENT_VERSION"
if [ "$SKIP_VERSION_CHECK" = "True" ] || [ "$(echo "$TARGET_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$CURRENT_VERSION" ]; then
    log_message "Proceeding with update"
else
    display_image_and_text "$IMAGE_PATH" 35 25 "System is up to date. Installed version: $CURRENT_VERSION" 75
    rm -rf "$TMP_DIR"
    sleep 5
    exit 0
fi

BATTERY_CAPACITY="$(cat $BATTERY/capacity)"
CHARGING="$(cat $BATTERY/online)"
if [ "$BATTERY_CAPACITY" -lt 20 ] && [ "$CHARGING" -eq 0 ]; then
    display_image_and_text "$IMAGE_PATH" 35 25 "Battery too low to complete update. You can still download it now, but you will need to charge your device to at least 20% or plug it in. Afterwards you may use the EZ Updater app to complete the update process." 75
    sleep 5
    log_message "OTA: Battery level: $BATTERY_CAPACITY%
    Charging: $CHARGING"
fi

update_qr_code="$(qr_code -t "$TARGET_INFO")"
display_image_and_text "$update_qr_code" 50 5 "Scan QR code for release notes. New version available: $TARGET_VERSION. Press A to download and install, or B to cancel." 75

if confirm 300; then
    log_message "OTA: User confirmed"
else
    log_message "OTA: User did not confirm"
    display_image_and_text "$BAD_IMG" 35 20 "Update cancelled." 75
    sleep 3
    rm -rf "$TMP_DIR"
    exit 0
fi

# Extract filename from TARGET_LINK
FILENAME=$(echo "$TARGET_LINK" | sed 's/.*\///')

# Check if update file already exists
if [ -f "/mnt/SDCARD/$FILENAME" ]; then
    display_image_and_text "$IMAGE_PATH" 35 25 "Update file already exists. Verifying..." 75
    log_message "OTA: Update file already exists"
    if verify_checksum "/mnt/SDCARD/$FILENAME" "$TARGET_CHECKSUM"; then
        display_image_and_text "$IMAGE_PATH" 35 25 "Valid update file already exists. Download again anyways? Press A to redownload, or B to use existing file for update."
        if ! confirm; then
            log_message "OTA: User chose to use existing file"
            rm -rf "$TMP_DIR"
            goto_install=true
        else
            rm -rf "/mnt/SDCARD/$FILENAME"
        fi
    else
        display_image_and_text "$IMAGE_PATH" 35 25 "Existing update file isn't valid. Will download fresh copy." 75
        sleep 3
    fi
fi

if [ "$goto_install" != "true" ]; then  # do the downloadin'
    # Check free disk space
    sdcard_mountpoint="$(mount | grep -m 1 "$SD_MOUNTPOINT" | awk '{print $1}')"
    sdcard_freespace="$(df -m "$sdcard_mountpoint" | awk 'NR==2{print $4}')"
    min_install_space=$(((TARGET_SIZE * 2) + 128))
    if [ "$free_space" -lt "$min_install_space" ]; then
        log_message "OTA: Not enough free space on SD card (at least ${min_install_space}MB should be free)"
        display_image_and_text "$IMAGE_PATH" 35 25 "Insufficient space on SD card. At least $min_install_space MB of space should be free." 75
        sleep 5
        rm -rf "$TMP_DIR"
        exit 1
    fi

    # Download update file
    display_image_and_text "$IMAGE_PATH" 35 25 "Downloading update..." 75
    if ! download_and_display_progress "$TARGET_LINK" "/mnt/SDCARD/$FILENAME" "spruce v${TARGET_VERSION}" "$((TARGET_SIZE * 1024 * 1024))"; then
        exit 1
    fi

    # Verify checksum
    display_image_and_text "$IMAGE_PATH" 35 25 "Download complete! Verifying..." 75
    if ! verify_checksum "/mnt/SDCARD/$FILENAME" "$TARGET_CHECKSUM"; then
        display_image_and_text "$BAD_IMG" 35 25 "File downloaded but failed verification. Try again..." 75
        sleep 5
        rm -rf "$TMP_DIR"
        exit 1
    fi
    vibrate &
fi

rm -rf "$TMP_DIR"
# Show updater app
sed -i 's|"#label"|"label"|' "/mnt/SDCARD/App/-Updater/config.json"

# Check battery level before asking to update
BATTERY_CAPACITY="$(cat $BATTERY/capacity)"
CHARGING="$(cat $BATTERY/online)"
if [ $BATTERY_CAPACITY -lt 20 ] && [ $CHARGING -eq 0 ]; then
    display_image_and_text "$BAD_IMG" 35 25 "Battery too low to safely update. Please charge to at least 20% or plug in your device. You can run the EZ Updater app to install the already downloaded update." 75
    sleep 5
    exit 0
fi

# Update script call
display_image_and_text "$IMAGE_PATH" 35 25 "Download successful! Press A to install now, or B to exit and install later." 75
if confirm 30 0; then
    log_message "OTA: Update confirmed"
    /mnt/SDCARD/App/-Updater/updater.sh
else
    log_message "OTA: Update declined"
    exit 0
fi
