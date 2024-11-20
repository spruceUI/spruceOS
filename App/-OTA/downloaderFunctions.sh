. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SD_CARD="/mnt/SDCARD"
OTA_URL="https://spruceui.github.io/OTA/spruce"
TMP_DIR="$SD_CARD/App/-OTA/tmp"
CONFIG_FILE="$SD_CARD/App/-OTA/config.json"


check_for_update() {

    mkdir -p "$TMP_DIR"

    # Check for Wi-Fi enabled status first
    wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$system_config_file")
    if [ "$wifi_enabled" -eq 0 ]; then
        log_message "Update Check: WiFi is disabled, exiting."
        rm -rf "$TMP_DIR"
        return 1
    fi

    # Try up to 3 times to get a connection
    attempts=0
    while [ $attempts -lt 3 ]; do
        if ping -c 3 spruceui.github.io >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        if [ $attempts -eq 3 ]; then
            log_message "Update Check: Failed to establish network connection after 3 attempts."
            rm -rf "$TMP_DIR"
            return 1
        fi
        log_message "Update Check: Waiting for network connection (attempt $attempts of 3)..."
        sleep 20
    done

    # Get current version based on mode
    if flag_check "developer_mode" || flag_check "tester_mode"; then
        CURRENT_VERSION=$(get_version_nightly)
    else
        CURRENT_VERSION=$(get_version)
    fi

    read_only_check

    log_message "Update Check: Current version: $CURRENT_VERSION"

    # Download and parse the release info file
    if ! curl -s -o "$TMP_DIR/spruce" "$OTA_URL"; then
        log_message "Update Check: Failed to download release info"
        rm -rf "$TMP_DIR"
        return 1
    fi

    # Extract version info from downloaded file
    RELEASE_VERSION=$(sed -n 's/RELEASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    RELEASE_CHECKSUM=$(sed -n 's/RELEASE_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    RELEASE_LINK=$(sed -n 's/RELEASE_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    RELEASE_SIZE=$(sed -n 's/RELEASE_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

    # Extract nightly info
    NIGHTLY_VERSION=$(sed -n 's/NIGHTLY_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_CHECKSUM=$(sed -n 's/NIGHTLY_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_LINK=$(sed -n 's/NIGHTLY_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_SIZE=$(sed -n 's/NIGHTLY_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

    # Set target version based on developer/tester mode
    TARGET_VERSION="$RELEASE_VERSION"
    if flag_check "developer_mode" || flag_check "tester_mode"; then
        TARGET_VERSION="$NIGHTLY_VERSION"
    fi

    # Compare versions, handling nightly date format
    log_message "Update Check: Comparing versions: $TARGET_VERSION vs $CURRENT_VERSION"
    
    # Extract base version and date for nightly builds
    current_base_version=$(echo "$CURRENT_VERSION" | cut -d'-' -f1)
    current_date=$(echo "$CURRENT_VERSION" | cut -d'-' -f2 -s)
    target_base_version=$(echo "$TARGET_VERSION" | cut -d'-' -f1)
    target_date=$(echo "$TARGET_VERSION" | cut -d'-' -f2 -s)

    update_available=0
    if [ "$(echo "$target_base_version $current_base_version" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$current_base_version" ]; then
        update_available=1
    elif [ -n "$current_date" ] && [ -n "$target_date" ] && [ "$target_date" -gt "$current_date" ]; then
        update_available=1
    fi

    if [ $update_available -eq 1 ]; then
        log_message "Update Check: Update available"
        # Update is available - show app and set label and description
        sed -i 's|"#label"|"label"|; 
                s|"label": "[^"]*"|"label": "Update Available"|;
                s|"description": "[^"]*"|"description": "Version '"$TARGET_VERSION"' is available"|' "$CONFIG_FILE"
        rm -rf "$TMP_DIR"
        return 0
    else
        log_message "Update Check: Current version is up to date"
        # No update - if app is visible, set label and description back to default
        if grep -q '"label"' "$CONFIG_FILE"; then
            sed -i 's|"label": "[^"]*"|"label": "Check for Updates"|;
                    s|"description": "[^"]*"|"description": "Check for updates over Wi-Fi"|' "$CONFIG_FILE"
        fi
        rm -rf "$TMP_DIR"
        return 1
    fi
}

download_progress() {
    local filepath="$1"
    local total_size_mb="$2"
    # Add start time tracking
    START_TIME=$(date +%s)
    local prev_size=0
    local downloadBar="/mnt/SDCARD/App/-OTA/imgs/downloadBar.png"
    local downloadFill="/mnt/SDCARD/App/-OTA/imgs/downloadFill.png"
    # Bar slider, 0.15 is 0, 0.85 is 100
    local fill_scale_int=15  # 0.15 * 100
    

    # Convert MB to bytes (1MB = 1048576 bytes)
    log_message "OTA: Total size: $total_size_mb MB"
    log_message "OTA: Filepath: $filepath"
    sleep 1

    while true; do
        # Check if file exists
        if [ ! -f "$filepath" ]; then
            log_message "File not found: $filepath"
            return 1
        fi

        # Get current size in bytes using POSIX-compliant ls -l
        CURRENT_SIZE=$(ls -ln "$filepath" 2>/dev/null | awk '{print $5}')
        CURRENT_SIZE_MB=$(($CURRENT_SIZE / 1048576))

        # Calculate ETA
        CURRENT_TIME=$(date +%s)
        ELAPSED_SECONDS=$((CURRENT_TIME - START_TIME))

        if [ "$ELAPSED_SECONDS" -gt 3 ] && [ "$CURRENT_SIZE" -gt "$prev_size" ]; then
            # Calculate speed in MB/s
            SPEED_MB=$(((CURRENT_SIZE_MB * 100) / (ELAPSED_SECONDS * 100)))
            # Calculate remaining MB
            REMAINING_MB=$((total_size_mb - CURRENT_SIZE_MB))
            # Calculate remaining seconds
            if [ "$SPEED_MB" -gt 0 ]; then
                REMAINING_SECONDS=$((REMAINING_MB / SPEED_MB))
                # Convert to minutes and seconds
                REMAINING_MIN=$((REMAINING_SECONDS / 60))
                REMAINING_SEC=$((REMAINING_SECONDS % 60))
                ETA_MSG="Time remaining: ${REMAINING_MIN}m ${REMAINING_SEC}s"
            else
                ETA_MSG="Download speed less than 1MB/s"
            fi
        else
            ETA_MSG="Time remaining: calculating..."
        fi

        PERCENTAGE=$(((CURRENT_SIZE_MB * 100) / total_size_mb))

        log_message "OTA: Download progress: $PERCENTAGE% (Size: $CURRENT_SIZE_MB / $total_size_mb MB)$ETA_MSG"

        # Calculate fill_scale_int based on percentage (15 to 85 range)
        # 0% = 15, 100% = 85, linear interpolation
        fill_scale_int=$((15 + (PERCENTAGE * 70 / 100)))

        display -t "Downloading update...
        

        
$PERCENTAGE%
$ETA_MSG" -p 135 --add-image $downloadFill 0.$(printf '%02d' $fill_scale_int) 240 left --add-image $downloadBar 1.0 240 middle

        # Update previous size for next iteration
        prev_size=$CURRENT_SIZE

        # Exit if download is complete (>= 99%)
        if [ "$PERCENTAGE" -ge 99 ]; then
            log_message "Download complete"
            break
        fi

        sleep 5
    done
}
