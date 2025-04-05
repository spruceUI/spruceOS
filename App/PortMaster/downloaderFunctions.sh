. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

SD_CARD="/mnt/SDCARD"
OTA_URL="https://spruceui.github.io/OTA/spruce"
TMP_DIR="$SD_CARD/App/-OTA/tmp"
CONFIG_FILE="$SD_CARD/App/-OTA/config.json"


check_for_update() {
    # Check if updates are enabled in settings
    if ! setting_get "checkForUpdates"; then
        return 1
    fi

    local timestamp_file="$SD_CARD/App/-OTA/last_check.timestamp"
    local check_interval=86400  # 24 hours in seconds

    # If update was previously prompted, check the timestamp
    if flag_check "update_prompted"; then
        # Create timestamp file if it doesn't exist
        [ ! -f "$timestamp_file" ] && date +%s > "$timestamp_file"
        
        current_time=$(date +%s)
        last_check=$(cat "$timestamp_file")
        time_diff=$((current_time - last_check))
        
        # If less than 24 hours have passed, skip the check
        if [ $time_diff -lt $check_interval ]; then
            log_message "Update Check: Skipping check, last check was $((time_diff / 3600)) hours ago"
            return 1
        fi
    fi

    mkdir -p "$TMP_DIR"

    # Update timestamp for next check
    date +%s > "$timestamp_file"

    # Check for Wi-Fi enabled status first
    wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$SYSTEM_JSON")
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
    if flag_check "developer_mode" || flag_check "tester_mode" || flag_check "beta"; then
        CURRENT_VERSION=$(get_version_complex)
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

    # Extract beta info
    BETA_VERSION=$(sed -n 's/BETA_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    BETA_CHECKSUM=$(sed -n 's/BETA_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    BETA_LINK=$(sed -n 's/BETA_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    BETA_SIZE=$(sed -n 's/BETA_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    BETA_INFO=$(sed -n 's/BETA_INFO=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

    # Set target version based on developer/tester mode
    TARGET_VERSION="$RELEASE_VERSION"
    if flag_check "beta"; then
        TARGET_VERSION="$BETA_VERSION"
    fi

    if flag_check "developer_mode" || flag_check "tester_mode"; then
        TARGET_VERSION="$NIGHTLY_VERSION"
    fi

    # Compare versions, handling nightly date format and beta versions
    log_message "Update Check: Comparing versions: $TARGET_VERSION vs $CURRENT_VERSION"
    
    # Extract base version, date, and beta status
    current_base_version=$(echo "$CURRENT_VERSION" | cut -d'-' -f1)
    current_suffix=$(echo "$CURRENT_VERSION" | cut -d'-' -f2 -s)
    current_is_beta=$(echo "$current_suffix" | grep -q "Beta" && echo "1" || echo "0")
    current_date=$(echo "$current_suffix" | grep -qE "^[0-9]{8}$" && echo "$current_suffix" || echo "")

    target_base_version=$(echo "$TARGET_VERSION" | cut -d'-' -f1)
    target_suffix=$(echo "$TARGET_VERSION" | cut -d'-' -f2 -s)
    target_is_beta=$(echo "$target_suffix" | grep -q "Beta" && echo "1" || echo "0")
    target_date=$(echo "$target_suffix" | grep -qE "^[0-9]{8}$" && echo "$target_suffix" || echo "")

    update_available=0
    
    # Compare base versions first
    version_higher=$(echo "$target_base_version $current_base_version" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print "0"; exit} else if (a[i]>b[i]) {print "1"; exit}} print "0"}')
    
    if [ "$version_higher" = "1" ]; then
        # Target version is higher, always consider it an update
        update_available=1
    elif [ "$version_higher" = "0" ] && [ "$target_base_version" = "$current_base_version" ]; then
        # Same base version, check suffixes
        if flag_check "developer_mode" || flag_check "tester_mode"; then
            # For testers/developers, nightlies are updates
            if [ -n "$target_date" ] && [ -n "$current_date" ] && [ "$target_date" -gt "$current_date" ]; then
                update_available=1
            fi
        elif flag_check "beta"; then
            # Beta mode logic
            if [ "$current_is_beta" = "1" ]; then
                # Currently on beta, only higher base versions are updates
                update_available=0
            elif [ "$target_is_beta" = "1" ]; then
                # Not on beta, but target is beta - consider it an update
                update_available=1
            fi
        fi
    fi

    if [ $update_available -eq 1 ]; then
        log_message "Update Check: Update available"
        # Update is available - show app and set label and description
        sed -i 's|"#label"|"label"|; 
                s|"label": "[^"]*"|"label": "Update Available"|;
                s|"description": "[^"]*"|"description": "Version '"$TARGET_VERSION"' is available"|' "$CONFIG_FILE"
        rm -rf "$TMP_DIR"

        # Check if update was previously prompted
        if ! flag_check "update_prompted"; then
            # First time seeing this update
            flag_add "update_available"
            flag_add "update_prompted"
            echo "$TARGET_VERSION" > "$(flag_path update_prompted)"
            echo "$TARGET_VERSION" > "$(flag_path update_available)"
        else
            # Get version from previous prompt
            prompted_version=$(cat "$(flag_path update_prompted)")
            
            # Compare versions (using same logic as above)
            prompted_base_version=$(echo "$prompted_version" | cut -d'-' -f1)
            prompted_date=$(echo "$prompted_version" | cut -d'-' -f2 -s)
            
            newer_than_prompted=0
            if [ "$(echo "$target_base_version $prompted_base_version" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$prompted_base_version" ]; then
                newer_than_prompted=1
            elif [ -n "$prompted_date" ] && [ -n "$target_date" ] && [ "$target_date" -gt "$prompted_date" ]; then
                newer_than_prompted=1
            fi

            if [ $newer_than_prompted -eq 1 ]; then
                # New version is newer than previously prompted version
                flag_add "update_available"
                echo "$TARGET_VERSION" > "$(flag_path update_prompted)"
                echo "$TARGET_VERSION" > "$(flag_path update_available)"
            fi
        fi
        return 0
    else
        log_message "Update Check: Current version is up to date"
        # No update - if app is visible, set label and description back to default
        if grep -q '"label"' "$CONFIG_FILE"; then
            sed -i 's|"label": "[^"]*"|"label": "Check for Updates"|;
                    s|"description": "[^"]*"|"description": "Download and install updates over Wi-Fi"|' "$CONFIG_FILE"
        fi
        rm -rf "$TMP_DIR"
        return 1
    fi
}

download_progress() {
    local filepath="$1"
    local total_size_mb="$2"
    local title="${3:-Downloading update...}"
    local grace_period="${4:-0}"
    
    START_TIME=$(date +%s)
    local prev_size=0
    local downloadBar="/mnt/SDCARD/App/-OTA/imgs/downloadBar.png"
    local downloadFill="/mnt/SDCARD/App/-OTA/imgs/downloadFill.png"
    local fill_scale_int=15

    log_message "Downloader: Total size: $total_size_mb MB"
    log_message "Downloader: Filepath: $filepath"

    # Wait for file to exist (30 second timeout)
    timeout_seconds=30
    start_time=$(date +%s)
    
    while [ ! -f "$filepath" ]; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout_seconds ]; then
            log_message "Downloader: Timeout reached after ${timeout_seconds}s - File not found: $filepath"
            return 1
        fi
        sleep 1
    done

    # Grace period check - if file completes within grace period, exit successfully
    sleep "$grace_period"
    
    # After grace period, check if download is already complete
    if [ -f "$filepath" ]; then
        CURRENT_SIZE=$(ls -ln "$filepath" 2>/dev/null | awk '{print $5}')
        CURRENT_SIZE_MB=$(($CURRENT_SIZE / 1048576))
        if [ "$CURRENT_SIZE_MB" -ge "$total_size_mb" ]; then
            log_message "Downloader: Download completed within grace period, skipping progress display"
            return 0
        fi
    fi

    while true; do
        # Check if file exists
        if [ ! -f "$filepath" ]; then
            log_message "Downloader: File not found: $filepath"
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

        log_message "Download progress: $PERCENTAGE% (Size: $CURRENT_SIZE_MB / $total_size_mb MB)$ETA_MSG"

        # Calculate fill_scale_int based on percentage (15 to 85 range)
        fill_scale_int=$((15 + (PERCENTAGE * 70 / 100)))

        if [ -n "$ETA_MSG" ]; then
            display -t "$title
        

        
$PERCENTAGE%
$ETA_MSG" -p 135 --add-image $downloadFill 0.$(printf '%02d' $fill_scale_int) 240 left --add-image $downloadBar 1.0 240 middle
        else
            display -t "$title
        

        
$PERCENTAGE%" -p 135 --add-image $downloadFill 0.$(printf '%02d' $fill_scale_int) 240 left --add-image $downloadBar 1.0 240 middle
        fi

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
