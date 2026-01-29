#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh

run_sd_card_fix_if_triggered() {
    needs_fix=false
    if [ -e /mnt/SDCARD/FIX_MY_SDCARD ]; then
        needs_fix=true
        log_message "/mnt/SDCARD/FIX_MY_SDCARD detected."
    elif read_only_check; then
        needs_fix=true
    fi

    if [ "$needs_fix" = "true" ]; then
        log_message "Running repairSD.sh..."
        mkdir -p /tmp/sdfix
        cp /mnt/SDCARD/spruce/scripts/tasks/repairSD.sh /tmp/sdfix/
        chmod 777 /tmp/sdfix/repairSD.sh
        /tmp/sdfix/repairSD.sh run
    fi
}

hide_fw_app() {
    sed -i 's|"label"|"#label"|' /mnt/SDCARD/App/-FirmwareUpdate-/config.json
}

show_fw_app() {
    sed -i 's|"#label"|"label"|' /mnt/SDCARD/App/-FirmwareUpdate-/config.json
}

# Define the function to check and hide the firmware update app
check_and_handle_firmware_app() {
    need_fw_update="$(check_if_fw_needs_update)"
    if [ "$need_fw_update" = "true" ]; then
        show_fw_app
    else
        hide_fw_app
    fi
}

check_for_update() {

    SD_CARD="/mnt/SDCARD"
    OTA_URL="https://spruceui.github.io/OTA/spruce"
    TMP_DIR="$SD_CARD/App/-OTA/tmp"
    CONFIG_FILE="$SD_CARD/App/-OTA/config.json"

    should_check="$(get_config_value '.menuOptions."System Settings".checkForUpdates.selected' "True")"
    if [ "$should_check" = "False" ]; then
        return 1
    fi

    timestamp_file="$SD_CARD/App/-OTA/last_check.timestamp"
    check_interval=86400  # 24 hours in seconds

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
    NIGHTLY_VERSION=$(sed -n 's/NIGHTLY_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    BETA_VERSION=$(sed -n 's/BETA_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

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

update_checker(){
    sleep 20
    check_for_update
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

# Function to check and hide the Update App if necessary
check_and_hide_update_app() {
    if ! check_for_update_file; then
        sed -i 's|"label"|"#label"|' "/mnt/SDCARD/App/-Updater/config.json"
        log_message "No update file found; hiding Updater app"
    else
        sed -i 's|"#label"|"label"|' "/mnt/SDCARD/App/-Updater/config.json"
        log_message "Update file found; Updater app is visible"
    fi
}

developer_mode_task() {
    if flag_check "developer_mode"; then
        samba_enabled="$(get_config_value '.menuOptions."Network Settings".enableSamba.selected' "False")"
        ssh_enabled="$(get_config_value '.menuOptions."Network Settings".enableSSH.selected' "False")"
        ssh_service=$(get_ssh_service_name)

        if [ "$samba_enabled" = "True" ] || [ "$ssh_enabled" = "True" ]; then
            # Loop until WiFi is connected
            while ! ifconfig wlan0 | grep -qE "inet |inet6 "; do
                sleep 0.2
            done

            if [ "$samba_enabled" = "True" ] && ! pgrep "smbd" > /dev/null; then
                log_message "Dev Mode: Samba starting..."
                start_samba_process
            fi

            if [ "$ssh_enabled" = "True" ] && ! pgrep "$ssh_service" > /dev/null; then
                log_message "Dev Mode: $ssh_service starting..."
                start_ssh_process
            fi
        fi
    fi
}

rotate_logs_background() {
        # Rotate logs spruce5.log -> spruce4.log -> spruce3.log -> etc.
        i=$((max_log_files - 1))
        while [ $i -ge 1 ]; do
            if [ -f "$log_dir/spruce${i}.log" ]; then
                mv "$log_dir/spruce${i}.log" "$log_dir/spruce$((i+1)).log"
            fi
            i=$((i - 1))
        done

        # Move the temporary file to spruce1.log
        if [ -f "$log_target.tmp" ]; then
            mv "$log_target.tmp" "$log_dir/spruce1.log"
        fi
}

rotate_logs() {
    log_dir="/mnt/SDCARD/Saves/spruce"
    log_target="$log_dir/spruce.log"
    max_log_files=5

    # Create the log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    # If spruce.log exists, move it to a temporary file
    if [ -f "$log_target" ]; then
        mv "$log_target" "$log_target.tmp"
    fi

    # Create a fresh spruce.log immediately
    touch "$log_target"

    # Perform log rotation in the background
    rotate_logs_background &
}

unstage_archive() {
    ARC_DIR="/mnt/SDCARD/spruce/archives"
    STAGED_ARCHIVE="$1"
    TARGET="$2"
    if [ -z "$TARGET_FOLDER" ] || [ "$TARGET_FOLDER" != "preCmd" ]; then TARGET="preMenu"; fi

    if [ -f "$ARC_DIR/staging/$STAGED_ARCHIVE" ]; then
        log_message "$STAGED_ARCHIVE detected in spruce/archives/staging. Moving into place!"
        mv -f "$ARC_DIR/staging/$STAGED_ARCHIVE" "$ARC_DIR/$TARGET/$STAGED_ARCHIVE"
    fi
}

unstage_archives_wanted() {
    if [ "$DISPLAY_WIDTH" = "640" ] && [ "$DISPLAY_HEIGHT" = "480" ]; then
        unstage_archive "overlays_640x480.7z" "preCmd"
    elif [ "$DISPLAY_WIDTH" = "1024" ] && [ "$DISPLAY_HEIGHT" = "768" ]; then
        unstage_archive "overlays_1024x768.7z" "preCmd"
    fi
    if [ "$DEVICE_CAN_USE_EXTERNAL_CONTROLLER" = "true" ]; then
        unstage_archive "autoconfig.7z" "preCmd"
    fi
    if [ "$DEVICE_USES_64_BIT_RA" = "true" ]; then
        unstage_archive "cores64.7z" "preCmd"
    else
        unstage_archive "cores32.7z" "preCmd"
    fi
}

UPDATE_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/firmwareupdate.png"

# This works with checker to display a notification if an update is available
# But only on next boot. So if they find the app by themselves it's fine.
update_notification(){
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
        exit 1
    fi

    if flag_check "update_available"; then
        available_version=$(cat "$(flag_path update_available)")
        display --icon "$UPDATE_ICON" -t "Update available!
Version ${available_version} is ready to install
Go to Apps and look for 'Update Available'" --okay
        flag_remove "update_available"
    fi
}
