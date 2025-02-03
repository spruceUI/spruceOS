#!/bin/sh

. "$HELPER_FUNCTIONS"

SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"

SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/bg_tree_sm.png"
FW_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/App/firmwareupdate.png"
WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
USER_THEME=$(get_theme_path_to_restore)

SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"

log_message "Starting firstboot script"

# initialize the settings... users can restore their own backup later.
cp "${SDCARD_PATH}/spruce/settings/system.json" "$SETTINGS_FILE"

# restore the user's theme in the "theme" field of the config.JSON
jq --arg new_theme "$USER_THEME" '.theme = $new_theme' "$SETTINGS_FILE" > tmp.json && mv tmp.json "$SETTINGS_FILE"

sync # Use sync just once to flush all changes of system.json to disk

# Copy spruce.cfg to www folder so the landing page can read it.
cp "/mnt/SDCARD/spruce/settings/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"

display -i "$SPRUCE_LOGO" -t "Installing spruce $SPRUCE_VERSION" -p 400
log_message "First boot flag detected"

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

log_message "Sorting themes"
sh /mnt/SDCARD/spruce/scripts/tasks/sortThemes.sh

sleep 3 # make sure installing spruce logo stays up longer; gives more time for XMB to unpack too

log_message "Displaying wiki image"
display -d 5 --icon "$WIKI_ICON" -t "Check out the spruce wiki on our GitHub page for tips and FAQs!"

VERSION=$(cat /usr/miyoo/version)
if [ "$VERSION" -lt 20240713100458 ]; then
    log_message "Detected firmware version $VERSION, turning off wifi and suggesting update"
    sed -i 's|"wifi":	1|"wifi":	0|g' "$SETTINGS_FILE"
    display -i "$BG_IMAGE" --icon "$FW_ICON" -d 5 -t "Visit the App section from the main menu to update your firmware to the latest version. It fixes the A30's Wi-Fi issues!"
fi

if flag_check "pre_menu_unpacking"; then
    display --icon "/mnt/SDCARD/spruce/imgs/iconfresh.png" -t "Finishing up unpacking themes and files.........."
    flag_remove "silentUnpacker"
    while flag_check "pre_menu_unpacking"; do
        sleep 0.3
    done
fi

log_message "Displaying enjoy image"
display -d 5 --icon "$HAPPY_ICON" -t "Happy gaming.........."

flag_remove "first_boot"
log_message "Removed first boot flag"
log_message "Finished firstboot script"
