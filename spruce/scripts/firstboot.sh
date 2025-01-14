#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

case "$PLATFORM" in
    "Brick" | "SmartPro" )
        INITIAL_SETTINGS="/mnt/SDCARD/spruce/settings/system-Brick.json"
        flag_remove "first_boot_Brick"
    ;;
    "Flip" )
        INITIAL_SETTINGS="/mnt/SDCARD/spruce/settings/system-Flip.json"
        flag_remove "first_boot_Flip"
    ;;
    "A30" )
        INITIAL_SETTINGS="/mnt/SDCARD/spruce/settings/system-A30.json"
        flag_remove "first_boot_A30"
    ;;
esac

log_message "Removed first boot flag for $PLATFORM"

SWAPFILE="/mnt/SDCARD/cachefile"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/bg_tree_sm.png"
FW_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/firmwareupdate.png"
WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
USER_THEME=$(get_theme_path_to_restore)

SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"

log_message "Starting firstboot script"

# initialize system settings.
cp "$INITIAL_SETTINGS" "$SYSTEM_JSON"

# restore the user's theme in the "theme" field of the config.JSON
jq --arg new_theme "$USER_THEME" '.theme = $new_theme' "$SYSTEM_JSON" > tmp.json && mv tmp.json "$SYSTEM_JSON"

sync # Use sync just once to flush all changes of system.json to disk

# Copy spruce.cfg to www folder so the landing page can read it.
cp "/mnt/SDCARD/spruce/settings/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"

display -i "$SPRUCE_LOGO" -t "Installing spruce $SPRUCE_VERSION" -p 400
log_message "First boot flag detected"

if [ "$PLATFORM" = "A30" ]; then

    # TODO: unwrap devconf from A30 check once network services are set up on Brick
    log_message "Running developer mode check" -v
    /mnt/SDCARD/spruce/scripts/devconf.sh > /dev/null &

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
fi

log_message "Running emu_setup.sh"
/mnt/SDCARD/Emu/.emu_setup/emu_setup.sh

log_message "Running emufresh.sh"
/mnt/SDCARD/spruce/scripts/emufresh_md5_multi.sh

log_message "Running iconfresh.sh"
/mnt/SDCARD/spruce/scripts/iconfresh.sh

log_message "Checking for DONTTOUCH theme"
if [ -d "/mnt/SDCARD/Themes/DONTTOUCH" ]; then
    log_message "DONTTOUCH theme found. Removing theme."
    rm -rf /mnt/SDCARD/Themes/DONTTOUCH
fi

sleep 3 # make sure installing spruce logo stays up longer; gives more time for XMB to unpack too

log_message "Displaying wiki image"
display -d 5 --icon "$WIKI_ICON" -t "Check out the spruce wiki on our GitHub page for tips and FAQs!"

# A30's firmware check
if [ "$PLATFORM" = "A30" ]; then
    VERSION=$(cat /usr/miyoo/version)
    if [ "$VERSION" -lt 20240713100458 ]; then
        log_message "Detected firmware version $VERSION, turning off wifi and suggesting update"
        sed -i 's|"wifi":	1|"wifi":	0|g' "$SYSTEM_JSON"
        display -i "$BG_IMAGE" --icon "$FW_ICON" -d 5 -t "Visit the App section from the main menu to update your firmware to the latest version. It fixes the A30's Wi-Fi issues!"
    fi
fi

# Disable stock USB file transfer app and SD formatter for Brick
if [ "$PLATFORM" = "Brick" ]; then
    USB_CONFIG="/usr/trimui/apps/usb_storage/config.json"
    [ -f "$USB_CONFIG" ] && sed -i "s|\"label|\"#label|g" "$USB_CONFIG" 2>/dev/null
    FORMAT_CONFIG="/usr/trimui/apps/zformatter_fat32/config.json"
    [ -f "$FORMAT_CONFIG" ] && sed -i "s|\"label|\"#label|g" "$FORMAT_CONFIG" 2>/dev/null
fi

if flag_check "pre_menu_unpacking"; then
    display --icon "/mnt/SDCARD/spruce/imgs/iconfresh.png" -t "Finishing up unpacking themes.........."
    while flag_check "pre_menu_unpacking"; do
        sleep 0.3
    done
fi

log_message "Displaying enjoy image"
display -d 5 --icon "$HAPPY_ICON" -t "Happy gaming.........."

log_message "Finished firstboot script"
