#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh

start_pyui_message_writer

flag_remove "first_boot_$PLATFORM"
log_message "Starting firstboot script on $PLATFORM"

WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
UNPACKING_ICON="/mnt/SDCARD/spruce/imgs/refreshing.png"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"


display_image_and_text "$SPRUCE_LOGO" 35 25 "Installing spruce $SPRUCE_VERSION" 75
sleep 5 # make sure installing spruce logo stays up longer; gives more time for XMB to unpack too

SSH_SERVICE_NAME=$(get_ssh_service_name)
if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
    log_message "Preparing SSH keys if necessary"
    dropbear_generate_keys &
fi

# Extract ScummVM standalone binaries in the background (64-bit only)
SCUMMVM_BG_PID=""
if [ "$PLATFORM_ARCHITECTURE" != "armhf" ]; then
    SCUMMVM_DIR="/mnt/SDCARD/Emu/SCUMMVM"
    SCUMMVM_HAS_ARCHIVES=""
    for SCUMMVM_7Z in "$SCUMMVM_DIR"/scummvm_*.7z; do
        [ -f "$SCUMMVM_7Z" ] && SCUMMVM_HAS_ARCHIVES=1 && break
    done
    if [ -n "$SCUMMVM_HAS_ARCHIVES" ]; then
        (
            for SCUMMVM_7Z in "$SCUMMVM_DIR"/scummvm_*.7z; do
                [ -f "$SCUMMVM_7Z" ] || continue
                7zr x -y -scsUTF-8 -o"$SCUMMVM_DIR" "$SCUMMVM_7Z" \
                    >>/mnt/SDCARD/Saves/spruce/scummvm_extract.log 2>&1
                rm -f "$SCUMMVM_7Z"
            done
        ) &
        SCUMMVM_BG_PID=$!
    fi
fi

if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ]; then
    mkdir -p /mnt/SDCARD/Persistent/
    if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
        extract_7z_with_progress /mnt/SDCARD/App/PortMaster/portmaster.7z /mnt/SDCARD/Persistent/ /mnt/SDCARD/Saves/spruce/portmaster_extract.log "Sprucing up your device"
    else
        display_image_and_text "$SPRUCE_LOGO" 35 25 "Sprucing up your device" 75
    fi

    rm -f /mnt/SDCARD/App/PortMaster/portmaster.7z
else
    display_image_and_text "$SPRUCE_LOGO" 35 25 "Sprucing up your device" 75
fi

# Wait for ScummVM extraction to finish
if [ -n "$SCUMMVM_BG_PID" ]; then
    wait "$SCUMMVM_BG_PID"
fi

display_image_and_text "$WIKI_ICON" 35 25 "Check out the spruce wiki on our GitHub page for tips and FAQs!" 75
sleep 5

perform_fw_check

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
