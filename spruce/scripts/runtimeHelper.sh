#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh
. /mnt/SDCARD/App/-OTA/downloaderFunctions.sh

# Define the function to check and hide the firmware update app
check_and_handle_firmware_app() {

    # Always hide firmware app in simple mode; don't bother checking platform
    if flag_check "simple_mode"; then
        mount -o bind /mnt/SDCARD/spruce/spruce /mnt/SDCARD/App/-FirmwareUpdate-/config.json
        return 0
    fi

    case "$PLATFORM" in
        "A30" )
            VERSION="$(cat /usr/miyoo/version)"
            if [ "$VERSION" -ge 20240713100458 ]; then
                mount -o bind /mnt/SDCARD/spruce/spruce /mnt/SDCARD/App/-FirmwareUpdate-/config.json
            fi
            ;;
        "Flip" )
            VERSION="$(cat /usr/miyoo/version)"
            if [ "$VERSION" -ge 20250228101926 ]; then
                mount --bind /mnt/SDCARD/spruce/spruce /mnt/SDCARD/App/-FirmwareUpdate-/config.json
            fi
            ;;
        "Brick" )
            VERSION="$(cat /etc/version)"
            v_major="$(cut -d '.' -f 1 "$VERSION")"
            # v_minor="$(cut -d '.' -f 2 "$VERSION")"
            v_bug="$(cut -d '.' -f 3 "$VERSION")"
            if [ "$v_major" -ge 1 ] && [ "$v_bug" -ge 6 ]; then
                mount --bind /mnt/SDCARD/spruce/spruce /mnt/SDCARD/App/-FirmwareUpdate-/config.json
            fi
            ;;
        "SmartPro" )
            VERSION="$(cat /etc/version)"
            v_major="$(cut -d '.' -f 1 "$VERSION")"
            # v_minor="$(cut -d '.' -f 2 "$VERSION")"
            v_bug="$(cut -d '.' -f 3 "$VERSION")"
            if [ "$v_major" -ge 1 ] && [ "$v_bug" -ge 4 ]; then
                mount --bind /mnt/SDCARD/spruce/spruce /mnt/SDCARD/App/-FirmwareUpdate-/config.json
            fi
            ;;
    esac
}

# Function to check and hide the Update App if necessary
check_and_hide_update_app() {
    . /mnt/SDCARD/Updater/updaterFunctions.sh
    if ! check_for_update_file; then
        sed -i 's|"label"|"#label"|' "/mnt/SDCARD/App/-Updater/config.json"
        log_message "No update file found; hiding Updater app"
    else
        sed -i 's|"#label"|"label"|' "/mnt/SDCARD/App/-Updater/config.json"
        log_message "Update file found; Updater app is visible"
    fi
    # override updaterFunctions keycodes
    . /mnt/SDCARD/spruce/scripts/helperFunctions.sh
}

check_and_move_p8_bins() {
    [ -f "/mnt/SDCARD/pico8.dat" ] && \
    [ ! -f "/mnt/SDCARD/Emu/PICO8/bin/pico8.dat" ] && \
    mv "/mnt/SDCARD/pico8.dat" "/mnt/SDCARD/Emu/PICO8/bin/pico8.dat" && \
    display -d 1.5 -t "pico8.dat found and moved into place." --icon "/mnt/SDCARD/Themes/SPRUCE/icons/pico.png" && \
    log_message "pico8.dat found at SD root and moved into place"
    
    [ -f "/mnt/SDCARD/pico8_dyn" ] && \
    [ ! -f "/mnt/SDCARD/Emu/PICO8/bin/pico8_dyn" ] && \
    mv "/mnt/SDCARD/pico8_dyn" "/mnt/SDCARD/Emu/PICO8/bin/pico8_dyn" && \
    display -d 1.5 -t "pico8_dyn found and moved into place." --icon "/mnt/SDCARD/Themes/SPRUCE/icons/pico.png" && \
    log_message "pico8_dyn found at SD root and moved into place"

    [ -f "/mnt/SDCARD/pico8_64" ] && \
    [ ! -f "/mnt/SDCARD/Emu/PICO8/bin/pico8_64" ] && \
    mv "/mnt/SDCARD/pico8_64" "/mnt/SDCARD/Emu/PICO8/bin/pico8_64" && \
    display -d 1.5 -t "pico8_64 found and moved into place." --icon "/mnt/SDCARD/Themes/SPRUCE/icons/pico.png" && \
    log_message "pico8_64 found at SD root and moved into place"
}

developer_mode_task() {
    if flag_check "developer_mode" || flag_check "designer_mode"; then
        if setting_get "samba" || setting_get "dropbear"; then
            # Loop until WiFi is connected
            while ! ifconfig wlan0 | grep -qE "inet |inet6 "; do
                sleep 0.5
            done
            
            if setting_get "samba" && ! pgrep "smbd" > /dev/null; then
                log_message "Dev Mode: Samba starting..."
                start_samba_process
            fi

            if setting_get "dropbear" && ! pgrep "dropbearmulti" > /dev/null; then
                log_message "Dev Mode: Dropbear starting..."
                start_dropbear_process
            fi
        fi
    fi
}

rotate_logs() {
    local log_dir="/mnt/SDCARD/Saves/spruce"
    local log_target="$log_dir/spruce.log"
    local max_log_files=5

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
    (
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
    ) &
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


unstage_archives_A30() {
    unstage_archive "Overlays.7z" "preCmd"
    unstage_archive "cores32.7z" "preCmd"
}

unstage_archives_Brick() {
    unstage_archive "autoconfig.7z" "preCmd"
    unstage_archive "cores64.7z" "preCmd"
}

unstage_archives_SmartPro() {
    unstage_archive "autoconfig.7z" "preCmd"
    unstage_archive "cores64.7z" "preCmd"
}

unstage_archives_Flip() {
    unstage_archive "Overlays.7z" "preCmd"
    unstage_archive "autoconfig.7z" "preCmd"
    unstage_archive "cores64.7z" "preCmd"
}

update_checker(){
    sleep 20
    check_for_update
}

UPDATE_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/firmwareupdate.png"

# This works with checker to display a notification if an update is available
# But only on next boot. So if they find the app by themselves it's fine.
update_notification(){
    wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$SYSTEM_JSON")
    if [ "$wifi_enabled" -eq 0 ]; then
        exit 1
    fi

    if flag_check "update_available" && ! flag_check "simple_mode"; then
        available_version=$(cat "$(flag_path update_available)")
        display --icon "$UPDATE_ICON" -t "Update available!
Version ${available_version} is ready to install
Go to Apps and look for 'Update Available'" --okay
        flag_remove "update_available"
    fi
}


