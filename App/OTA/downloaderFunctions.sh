. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SD_CARD="/mnt/SDCARD"
OTA_URL="https://spruceui.github.io/OTA/spruce"
TMP_DIR="$SD_CARD/App/OTA/tmp"
CONFIG_FILE="$SD_CARD/App/OTA/config.json"


check_for_update() {

    mkdir -p "$TMP_DIR"

    # Check for Wi-Fi and active connection
    wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$system_config_file")
    if [ "$wifi_enabled" -eq 0 ] || ! ping -c 3 spruceui.github.io >/dev/null 2>&1; then
        log_message "Update Check: No active network connection, exiting."
        rm -rf "$TMP_DIR"
        return 1
    fi

    CURRENT_VERSION=$(get_version)

    read_only_check

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

    if [ -z "$RELEASE_VERSION" ] || [ -z "$RELEASE_CHECKSUM" ] || [ -z "$RELEASE_LINK" ] || [ -z "$RELEASE_SIZE" ]; then
        log_message "Update Check: Invalid release info file format"
        rm -rf "$TMP_DIR"
        return 1
    fi

    # Compare versions
    log_update_message "Comparing versions: $RELEASE_VERSION vs $CURRENT_VERSION"
    if [ "$(echo "$RELEASE_VERSION $CURRENT_VERSION" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$CURRENT_VERSION" ]; then
        log_update_message "Update available"
        # Update is available - show app and set label to "Update Available"
        sed -i 's|"#label"|"label"|; s|"label": "[^"]*"|"label": "Update Available"|' "$CONFIG_FILE"
        rm -rf "$TMP_DIR"
        return 0
    else
        log_update_message "Current version is up to date"
        # No update - if app is visible, set label to "Check for Updates"
        if grep -q '"label"' "$CONFIG_FILE"; then
            sed -i 's|"label": "[^"]*"|"label": "Check for Updates"|' "$CONFIG_FILE"
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

        if [ "$ELAPSED_SECONDS" -gt 0 ] && [ "$CURRENT_SIZE" -gt "$prev_size" ]; then
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
                ETA_MSG="Time remaining: calculating..."
            fi
        else
            ETA_MSG="Time remaining: calculating..."
        fi

        PERCENTAGE=$(((CURRENT_SIZE_MB * 100) / total_size_mb))

        log_message "OTA: Download progress: $PERCENTAGE% (Size: $CURRENT_SIZE_MB / $total_size_mb MB)$ETA_MSG"

        # Calculate filled and empty segments of progress bar (20 chars total)
        FILLED_CHARS=$((PERCENTAGE / 5))
        EMPTY_CHARS=$((20 - FILLED_CHARS))
        PROGRESS_BAR=""

        # Build progress bar string
        i=0
        while [ $i -lt $FILLED_CHARS ]; do
            PROGRESS_BAR="${PROGRESS_BAR}="
            i=$((i + 1))
        done
        while [ $i -lt 20 ]; do
            PROGRESS_BAR="${PROGRESS_BAR}   "
            i=$((i + 1))
        done

        # Update display with ETA and progress bar
        display --icon "$IMAGE_PATH" -t "Downloading update... $PERCENTAGE%
$ETA_MSG
[${PROGRESS_BAR}]"

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
