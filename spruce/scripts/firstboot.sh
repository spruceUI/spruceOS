#!/bin/sh

. "$HELPER_FUNCTIONS"

SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"

BG_IMAGE="/mnt/SDCARD/spruce/imgs/displayTextPreColor.png"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/spruce_logo.png"
FW_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/App/firmwareupdate.png"
ICONFRESH_ICON="/mnt/SDCARD/Themes/SPRUCE/App/iconfresh.png"
WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"

log_message "Starting firstboot script"

if flag_check "first_boot"; then
    display -i "$BG_IMAGE" --icon "$SPRUCE_LOGO" -t "Installing spruce v3.0.0!" -p bottom
    log_message "First boot flag detected"
    
    # don't overwrite user's config if it's not a TRUE first boot
    if ! flag_check "config_copied"; then
        cp "${SDCARD_PATH}/.tmp_update/system.json" "$SETTINGS_FILE"
        flag_add "config_copied"
        sync
        sleep 5  ### why is this here? -Ry
        log_message "Copied system.json and created config_copied.lock"
    fi
    
    if [ -f "${SWAPFILE}" ]; then
        SWAPSIZE=$(du -k "${SWAPFILE}" | cut -f1)
        MINSIZE=$((128 * 1024))
        if [ "$SWAPSIZE" -lt "$MINSIZE" ]; then
            swapoff "${SWAPFILE}"
            rm "${SWAPFILE}"
            log_message "Removed undersized swap file"
        fi
    fi
    
    if [ ! -f "${SWAPFILE}" ]; then
        dd if=/dev/zero of="${SWAPFILE}" bs=1M count=128
        mkswap "${SWAPFILE}"
        sync
        log_message "Created new swap file"
    fi
    
    log_message "Running emu_setup.sh"
    /mnt/SDCARD/Emu/.emu_setup/emu_setup.sh &
    
    log_message "Running emufresh.sh"
    /mnt/SDCARD/spruce/scripts/emufresh_md5_multi.sh
    
    log_message "Running iconfresh.sh"
    display -p bottom -t "Refreshing icons... please wait......" -i "$BG_IMAGE" --icon "$ICONFRESH_ICON"
    /mnt/SDCARD/spruce/scripts/iconfresh.sh --silent

    log_message "Displaying wiki image"
    display -d 5 -i "$BG_IMAGE" --icon "$WIKI_ICON" -p bottom -t "Check out the spruce wiki on our GitHub page for tips and FAQs!"

    VERSION=$(cat /usr/miyoo/version)
    if [ "$VERSION" -lt 20240713100458 ]; then
        log_message "Detected firmware version $VERSION, suggesting update"
        display -i "$BG_IMAGE" --icon "$FW_ICON" -d 5 -p bottom -t "Visit the App section from the main menu to update your firmware to the latest version. It fixes the A30's Wi-Fi issues!"
    fi
    
    log_message "Displaying enjoy image"
    display -d 5 -i "$BG_IMAGE" --icon "$HAPPY_ICON" -p bottom -t "Happy gaming..........!"

    flag_remove "first_boot"
    log_message "Removed first boot flag"
else
    log_message "First boot flag not found. Skipping first boot procedures."
fi

log_message "Finished firstboot script"
