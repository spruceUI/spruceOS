#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh

start_pyui_message_writer

flag_remove "first_boot_$PLATFORM"
log_message "Starting firstboot script on $PLATFORM"

FW_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/firmwareupdate.png"
WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
UNPACKING_ICON="/mnt/SDCARD/spruce/imgs/refreshing.png"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"


display_image_and_text "$SPRUCE_LOGO" 35 25 "Installing spruce $SPRUCE_VERSION" 75
sleep 5 # make sure installing spruce logo stays up longer; gives more time for XMB to unpack too

log_message "Preparing SSH keys if necessary"
dropbear_generate_keys &

if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ]; then
    mkdir -p /mnt/SDCARD/Persistent/
    display_image_and_text "$SPRUCE_LOGO" 35 25 "Extracting PortMaster!" 75
    if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
        gzip -d /mnt/SDCARD/App/PortMaster/pm.tar.gz
        tar -xvf /mnt/SDCARD/App/PortMaster/pm.tar -C /mnt/SDCARD/Persistent
        rm -f /mnt/SDCARD/App/PortMaster/pm.tar
    else
        rm -f /mnt/SDCARD/App/PortMaster/pm.tar.gz
    fi
fi

display_image_and_text "$WIKI_ICON" 35 25 "Check out the spruce wiki on our GitHub page for tips and FAQs!" 75
sleep 5

# A30's firmware check
if [ "$PLATFORM" = "A30" ]; then
    VERSION=$(cat /usr/miyoo/version)
    if [ "$VERSION" -lt 20240713100458 ]; then
        log_message "Detected firmware version $VERSION, turning off wifi and suggesting update"
        sed -i 's|"wifi":	1|"wifi":	0|g' "$SYSTEM_JSON"
        display_image_and_text "$FW_ICON" 35 25 "Visit the App section from the main menu to update your firmware to the latest version. It fixes the A30's Wi-Fi issues!" 75
        sleep 5
    fi
fi

if flag_check "pre_menu_unpacking"; then
    display_image_and_text "$UNPACKING_ICON" 35 25 "Finishing up unpacking themes and files.........." 75
    flag_remove "silentUnpacker"
    while flag_check "pre_menu_unpacking"; do
        sleep 0.2
    done
fi

# create splore launcher if it doesn't already exist
if [ ! -f "$SPLORE_CART" ]; then
	touch "$SPLORE_CART" && log_message "firstboot.sh: created $SPLORE_CART"
else
	log_message "firstboot.sh: $SPLORE_CART already found."
fi

"$(get_python_path)" -O -m compileall /mnt/SDCARD/App/PyUI/main-ui/

display_image_and_text "$HAPPY_ICON" 35 25 "Happy gaming.........." 75
sleep 5

log_message "Finished firstboot script"
