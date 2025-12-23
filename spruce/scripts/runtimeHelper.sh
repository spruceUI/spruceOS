#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh

case "$PLATFORM" in
    "A30") export SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo/etc" ;;
    "Flip") export SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo355/etc" ;;
    "Brick" | "SmartPro" | "SmartProS" ) export SPRUCE_ETC_DIR="/mnt/SDCARD/trimui/etc" ;;
esac

run_sd_card_fix_if_triggered() {
    if [ -e /mnt/SDCARD/FIX_MY_SDCARD ]; then
        log_message "/mnt/SDCARD/FIX_MY_SDCARD detected. Running repairSD.sh..."
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

compare_current_version_to_version() {
    target_version="$1"
    current_version="$(cat /etc/version 2>/dev/null)"

    [ -z "$target_version" ] && target_version="1.0.0"
    [ -z "$current_version" ] && current_version="1.0.0"

    # Split versions into components
    C_1=$(echo "$current_version" | cut -d. -f1)
    C_2=$(echo "$current_version" | cut -d. -f2)
    C_3=$(echo "$current_version" | cut -d. -f3)
    C_2=${C_2:-0}
    C_3=${C_3:-0}

    T_1=$(echo "$target_version" | cut -d. -f1)
    T_2=$(echo "$target_version" | cut -d. -f2)
    T_3=$(echo "$target_version" | cut -d. -f3)
    T_2=${T_2:-0}
    T_3=${T_3:-0}

    i=1
    while [ $i -le 3 ]; do
        eval C=\$C_$i
        eval T=\$T_$i

        if [ "$C" -gt "$T" ]; then
            echo "newer"
            return 0
        elif [ "$C" -lt "$T" ]; then
            echo "older"
            return 2
        fi
        i=$((i + 1))
    done

    echo "same"
    return 1
}

check_if_fw_needs_update() {
    case "$PLATFORM" in
        "A30"|"Flip" )
            VERSION="$(cat /usr/miyoo/version)"
            [ "$VERSION" -ge "$TARGET_FW_VERSION" ] && echo "false" || echo "true"
            ;;
        "Brick"|"SmartPro"|"SmartProS" )
            current_fw_is="$(compare_current_version_to_version "$TARGET_FW_VERSION")"
            [ "$current_fw_is" != "older" ] && echo "false" || echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
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

        if [ "$samba_enabled" = "True" ] || [ "$ssh_enabled" = "True" ]; then
            # Loop until WiFi is connected
            while ! ifconfig wlan0 | grep -qE "inet |inet6 "; do
                sleep 0.2
            done
            
            if [ "$samba_enabled" = "True" ] && ! pgrep "smbd" > /dev/null; then
                log_message "Dev Mode: Samba starting..."
                start_samba_process
            fi

            if [ "$ssh_enabled" = "True" ] && ! pgrep "dropbearmulti" > /dev/null; then
                log_message "Dev Mode: Dropbear starting..."
                start_dropbear_process
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
        unstage_archive "Overlays.7z" "preCmd"
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

runtime_mounts_A30() {
    mkdir -p /var/lib/alsa
    mkdir -p /mnt/SDCARD/spruce/dummy
    mount -o bind "/mnt/SDCARD/miyoo/var/lib" /var/lib &
    mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib &
    mount -o bind /mnt/SDCARD/miyoo/res/skin /usr/miyoo/res/skin &
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    /mnt/SDCARD/spruce/a30/sdl2/bind.sh &
    wait
    touch /mnt/SDCARD/spruce/bin/python/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/bin/python/bin/python3.10 /mnt/SDCARD/spruce/bin/python/bin/MainUI
}

runtime_mounts_Brick() {
    # Mask Roms/PORTS with non-A30 version
    mkdir -p "/mnt/SDCARD/Roms/PORTS64"
    mount --bind "/mnt/SDCARD/Roms/PORTS64" "/mnt/SDCARD/Roms/PORTS" &    
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    /mnt/SDCARD/spruce/brick/sdl2/bind.sh &
    wait
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3 /mnt/SDCARD/spruce/flip/bin/MainUI
}

runtime_mounts_SmartPro() {
   runtime_mounts_Brick
}

runtime_mounts_SmartProS() {
   runtime_mounts_Brick
}

runtime_mounts_MiyooMini() {
    mount --bind /mnt/SDCARD/spruce/miyoomini/Emu /mnt/SDCARD/Emu
    mount --bind /mnt/SDCARD/spruce/miyoomini/RetroArch /mnt/SDCARD/RetroArch
}

runtime_mounts_Flip() {

    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &

    if [ ! -d /mnt/sdcard/Saves/userdata-flip ]; then
        log_message "Saves/userdata-flip does not exist. Populating surrogate /userdata directory"
        mkdir /mnt/sdcard/Saves/userdata-flip
        cp -R /userdata/* /mnt/sdcard/Saves/userdata-flip
        mkdir -p /mnt/sdcard/Saves/userdata-flip/bin
        mkdir -p /mnt/sdcard/Saves/userdata-flip/bluetooth
        mkdir -p /mnt/sdcard/Saves/userdata-flip/cfg
        mkdir -p /mnt/sdcard/Saves/userdata-flip/localtime
        mkdir -p /mnt/sdcard/Saves/userdata-flip/timezone
        mkdir -p /mnt/sdcard/Saves/userdata-flip/lib
        mkdir -p /mnt/sdcard/Saves/userdata-flip/lib/bluetooth
    fi

	if [ ! -f /mnt/SDCARD/Saves/userdata-flip/system.json ]; then
		cp /mnt/SDCARD/spruce/flip/miyoo_system.json /mnt/SDCARD/Saves/userdata-flip/system.json
	fi

    log_message "Mounting surrogate /userdata and /userdata/bluetooth folders"
    mount --bind /mnt/sdcard/Saves/userdata-flip/ /userdata
    mkdir -p /run/bluetooth_fix
    mount --bind /run/bluetooth_fix /userdata/bluetooth
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI

    /mnt/sdcard/spruce/flip/recombine_large_files.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/setup_32bit_chroot.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/mount_muOS.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/setup_32bit_libs.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/bind_glibc.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1

    # use appropriate loading images
    [ -d "/mnt/SDCARD/miyoo355/app/skin" ] && mount --bind /mnt/SDCARD/miyoo355/app/skin /usr/miyoo/bin/skin
    
    # Mask Roms/PORTS with non-A30 version
    mkdir -p "/mnt/SDCARD/Roms/PORTS64"
    mount --bind "/mnt/SDCARD/Roms/PORTS64" "/mnt/SDCARD/Roms/PORTS" &

	# PortMaster ports location
    mkdir -p /mnt/sdcard/Roms/PORTS64/ports/ 
    mount --bind /mnt/sdcard/Roms/PORTS64/ /mnt/sdcard/Roms/PORTS64/ports/
	
	# Treat /spruce/flip/ as the 'root' for any application that needs it.
	# (i.e. PortMaster looks here for config information which is device specific)
    mount --bind /mnt/sdcard/spruce/flip/ /root 

    # Bind the correct version of retroarch so it can be accessed by PM
    mount --bind /mnt/sdcard/RetroArch/retroarch-flip /mnt/sdcard/RetroArch/retroarch
}

perform_fw_update_Flip() {
    miyoo_fw_update=0
    miyoo_fw_dir=/media/sdcard0
    if [ -f /media/sdcard0/miyoo355_fw.img ] ; then
        miyoo_fw_update=1
        miyoo_fw_dir=/media/sdcard0
    elif [ -f /media/sdcard1/miyoo355_fw.img ] ; then
        miyoo_fw_update=1
        miyoo_fw_dir=/media/sdcard1
    fi

    if [ ${miyoo_fw_update} -eq 1 ] ; then
        cd $miyoo_fw_dir
        /usr/miyoo/apps/fw_update/miyoo_fw_update
        rm "${miyoo_fw_dir}/miyoo355_fw.img"
    fi
}

init_gpio_Flip() {
    # Initialize rumble motor
    echo 20 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio20/direction
    echo -n 0 > /sys/class/gpio/gpio20/value

    # Initialize headphone jack
    if [ ! -d /sys/class/gpio/gpio150 ]; then
        echo 150 > /sys/class/gpio/export
        sleep 0.1
    fi
    echo in > /sys/class/gpio/gpio150/direction
}

init_gpio_Brick() {
    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio107/direction
    echo -n 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio227/direction
    echo -n 0 > /sys/class/gpio/gpio227/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction
}

init_gpio_SmartPro() {
    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio107/direction
    echo -n 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio227/direction
    echo -n 0 > /sys/class/gpio/gpio227/value

    #Left/Right Pad PD14/PD18
    echo 110 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio110/direction
    echo -n 1 > /sys/class/gpio/gpio110/value

    echo 114 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio114/direction
    echo -n 1 > /sys/class/gpio/gpio114/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction
}

init_gpio_SmartProS() {
    #5V enable
    # echo 335 > /sys/class/gpio/export
    # echo -n out > /sys/class/gpio/gpio335/direction
    # echo -n 1 > /sys/class/gpio/gpio335/value

    #fan off
    echo 0 > /sys/class/thermal/cooling_device0/cur_state 

    #rumble motor PH12
    echo 236 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio236/direction
    echo -n 0 > /sys/class/gpio/gpio236/value

    #Left/Right Pad PK12/PK16 , run in trimui_inputd
    # echo 332 > /sys/class/gpio/export
    # echo -n out > /sys/class/gpio/gpio332/direction
    # echo -n 1 > /sys/class/gpio/gpio332/value

    # echo 336 > /sys/class/gpio/export
    # echo -n out > /sys/class/gpio/gpio336/direction
    # echo -n 1 > /sys/class/gpio/gpio336/value

    #DIP Switch PL11 , run in trimui_inputd
    # echo 363 > /sys/class/gpio/export
    # echo -n in > /sys/class/gpio/gpio363/direction

    # load wifi and low power bluetooth modules
    modprobe aic8800_fdrv.ko
    modprobe aic8800_btlpm.ko

    #splash rumble
    echo 32768 > /sys/class/motor/level 
    sleep 0.2
    echo 0 > /sys/class/motor/level 
}

run_trimui_blobs() {

    cd /usr/trimui/bin || return 1
    mkdir -p /tmp/trimui_inputd

    for blob in trimui_inputd trimui_thermald keymon trimui_scened \
                trimui_btmanager hardwareservice musicserver; do
        if [ -x "/usr/trimui/bin/$blob" ]; then
            LD_LIBRARY_PATH=/usr/trimui/lib "./$blob" &
            log_message "Attempted to start $blob"
        else
            log_message "$blob not found. Skipping."
        fi
    done

    if [ -x "/usr/trimui/osd/trimui_osdd" ]; then
        cd /usr/trimui/osd || return 1
        LD_LIBRARY_PATH=/usr/trimui/lib ./trimui_osdd &
        log_message "Attempted to start trimui_osdd"
    else
        log_message "trimui_osdd not found. Skipping."
    fi
}