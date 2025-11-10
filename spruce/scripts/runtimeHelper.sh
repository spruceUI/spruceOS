#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh
. /mnt/SDCARD/App/-OTA/downloaderFunctions.sh

case "$PLATFORM" in
    "A30" | "Brick" | "SmartPro" ) export SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo/etc" ;;
    "Flip") export SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo355/etc" ;;
esac

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
    [ ! -f "/mnt/SDCARD/BIOS/pico8.dat" ] && \
    mv "/mnt/SDCARD/pico8.dat" "/mnt/SDCARD/BIOS/pico8.dat" && \
    display -d 1.5 -t "pico8.dat found and moved into place." --icon "/mnt/SDCARD/Themes/SPRUCE/icons/pico.png" && \
    log_message "pico8.dat found at SD root and moved into place"
    
    [ -f "/mnt/SDCARD/pico8_dyn" ] && \
    [ ! -f "/mnt/SDCARD/BIOS/pico8_dyn" ] && \
    mv "/mnt/SDCARD/pico8_dyn" "/mnt/SDCARD/BIOS/pico8_dyn" && \
    display -d 1.5 -t "pico8_dyn found and moved into place." --icon "/mnt/SDCARD/Themes/SPRUCE/icons/pico.png" && \
    log_message "pico8_dyn found at SD root and moved into place"

    [ -f "/mnt/SDCARD/pico8_64" ] && \
    [ ! -f "/mnt/SDCARD/BIOS/pico8_64" ] && \
    mv "/mnt/SDCARD/pico8_64" "/mnt/SDCARD/BIOS/pico8_64" && \
    display -d 1.5 -t "pico8_64 found and moved into place." --icon "/mnt/SDCARD/Themes/SPRUCE/icons/pico.png" && \
    log_message "pico8_64 found at SD root and moved into place"
}

developer_mode_task() {
    if flag_check "developer_mode"; then
        if setting_get "samba" || setting_get "dropbear"; then
            # Loop until WiFi is connected
            while ! ifconfig wlan0 | grep -qE "inet |inet6 "; do
                sleep 0.2
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
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
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

runtime_mounts_A30() {
    mkdir -p /var/lib/alsa
    mkdir -p /mnt/SDCARD/spruce/dummy
    mount -o bind "/mnt/SDCARD/miyoo/var/lib" /var/lib &
    mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib &
    mount -o bind /mnt/SDCARD/miyoo/res /usr/miyoo/res &
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

    log_message "Mounting surrogate /userdata and /userdata/bluetooth folders"
    mount --bind /mnt/sdcard/Saves/userdata-flip/ /userdata
    mkdir -p /run/bluetooth_fix
    mount --bind /run/bluetooth_fix /userdata/bluetooth
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3 /mnt/SDCARD/spruce/flip/bin/MainUI

    /mnt/sdcard/spruce/flip/recombine_large_files.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/setup_32bit_chroot.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/mount_muOS.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/setup_32bit_libs.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/bind_glibc.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1

    # Use shared RA config between Miyoo in-game menu and non-Miyoo RA bins
    mount --bind "/mnt/SDCARD/spruce/settings/platform/retroarch-Flip.cfg" "/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"

    # use appropriate loading images
    [ -d "/mnt/SDCARD/miyoo355/app/skin" ] && mount --bind /mnt/SDCARD/miyoo355/app/skin /usr/miyoo/bin/skin
    [ -d "/mnt/SDCARD/miyoo355/app/lang" ] && mount --bind /mnt/SDCARD/miyoo355/app/lang /usr/miyoo/bin/lang
    
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