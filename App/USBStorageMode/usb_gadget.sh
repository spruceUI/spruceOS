#!/bin/sh

# USB Storage Mode gadget layer. Sourced by launch.sh (configure the gadget)
# and by save_poweroff.sh --usb-storage (release it during the shutdown).
# Needs $PLATFORM from helperFunctions.sh. Nothing here is executed on load.
#
# Why the release lives in the shutdown and not in the app (SPR-HIGH-053):
# on TrimUI stock, udev's block `watch` rule turns the mass-storage LUN
# closing /dev/mmcblk1p1 into a synthesized `change` uevent, which
# /sbin/mdev answers with /etc/mdev/sdcard_remove - the card is lazily
# unmounted, its mount point and /mnt/SDCARD are deleted. Anything the exit
# still needs from the card must therefore be in place BEFORE
# usb_gadget_release runs; save_poweroff.sh stages stage 2 into /tmp first.

# Platform table. Returns 1 on a platform without USB Storage Mode support.
usb_gadget_platform_setup() {
    case "$PLATFORM" in
        "A30")
            STORAGE_DEVICE="/dev/mmcblk0p1"
            MOUNT_POINT="/mnt/SDCARD"
            USB_GADGET_PATH="/sys/devices/platform/sunxi_usb_udc/gadget"
            LUN_PATH="$USB_GADGET_PATH/lun0"
            LUN_FILE="$LUN_PATH/file"
            ;;
        "Brick" | "SmartPro" | "BrickPro")
            STORAGE_DEVICE="/dev/mmcblk1p1"
            MOUNT_POINT="/mnt/SDCARD"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
            ;;
        "Flip")
            STORAGE_DEVICE="/dev/mmcblk1p1"
            MOUNT_POINT="/mnt/SDCARD"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
            USB_UDC_CONTROLLER="fcc00000.dwc3"
            USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"
            ;;
        "Pixel2")
            STORAGE_DEVICE="/dev/mmcblk0p3"
            MOUNT_POINT="/mnt/SDCARD/"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
            USB_UDC_CONTROLLER="ff300000.usb"
            USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"
            ;;
        "SmartProS")
            STORAGE_DEVICE="/dev/mmcblk1p1"
            MOUNT_POINT="/mnt/sdcard/mmcblk1p1"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
            USB_UDC_CONTROLLER="4100000.udc-controller"
            USB_CONFIG_PATH="$USB_GADGET_PATH/configs/c.1"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

safe_unmount_all() {
    for mpoint in $(mount | grep "$STORAGE_DEVICE" | awk '{print $3}' | sort -r); do
        for i in 1 2 3 4 5; do
            ! mount | grep -q " $mpoint " && break
            sync
            umount "$mpoint" 2>/dev/null && break
            sleep 1
        done
        if mount | grep -q " $mpoint "; then
            umount -f "$mpoint" 2>/dev/null
        fi
    done
    if grep -q "$MOUNT_POINT" /proc/mounts; then
        umount -f "$MOUNT_POINT" 2>/dev/null
    fi
}

# Release the mass-storage gadget: hand the block device back, unbind the
# UDC, drop the configuration link. Gadget only - no mounting or unmounting
# (save_poweroff.sh and stage 2 own the card from here on).
usb_gadget_release() {
    sync
    echo 3 > /proc/sys/vm/drop_caches
    case "$PLATFORM" in
        "A30")
            echo "" > "$LUN_FILE" 2>/dev/null
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            ;;
        "Brick" | "SmartPro" | "BrickPro")
            echo "" > $USB_GADGET_PATH/UDC 2>/dev/null
            rm -f $USB_GADGET_PATH/configs/c.1/mass_storage.usb0
            [ -d "$USB_GADGET_PATH/configs/c.1" ] && rmdir "$USB_GADGET_PATH/configs/c.1" 2>/dev/null
            [ -d "$USB_GADGET_PATH/functions/mass_storage.usb0" ] && rmdir "$USB_GADGET_PATH/functions/mass_storage.usb0" 2>/dev/null
            [ -d "$USB_GADGET_PATH/strings/0x409" ] && rmdir "$USB_GADGET_PATH/strings/0x409" 2>/dev/null
            ;;
        "Flip" | "Pixel2")
            echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            sleep 1
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            echo "" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
            rm -f "$USB_CONFIG_PATH/mass_storage.0" 2>/dev/null
            ;;
        "SmartProS")
            echo "" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
            sleep 1
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            sleep 2
            rm -f "$USB_CONFIG_PATH/mass_storage.0" 2>/dev/null
            ;;
    esac
    sync
}

# Legacy path: export with the card still mounted. Only for platforms whose
# system owns the card (device_system_handles_sdcard_unmount), where the
# card-less session below cannot take it away. Everywhere else the PC would
# be handed a filesystem the kernel still has mounted read-write (SPR-MED-198).
configure_usb_gadget() {
    log_message "Configuring USB gadget for $PLATFORM..."
    safe_unmount_all
    sync
    echo 3 > /proc/sys/vm/drop_caches
    usb_export_gadget
}

# Write the LUN, build the configuration, bind the UDC. Pure gadget work: the
# caller decides what state the card is in.
usb_export_gadget() {

    case "$PLATFORM" in
        "A30")
            echo "" > "$LUN_FILE" 2>/dev/null
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            sleep 1
            [ -f "$LUN_PATH/ro" ] && echo 0 > "$LUN_PATH/ro" 2>/dev/null
            [ -f "$LUN_PATH/nofua" ] && echo 0 > "$LUN_PATH/nofua" 2>/dev/null
            [ -f "$LUN_PATH/removable" ] && echo 1 > "$LUN_PATH/removable" 2>/dev/null
            echo "$STORAGE_DEVICE" > "$LUN_FILE" 2>/dev/null
            sleep 1
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 1 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            ;;
        "Brick" | "SmartPro" | "BrickPro")
            mkdir -p $USB_GADGET_PATH/functions/mass_storage.usb0
            echo "0x1d6b" > $USB_GADGET_PATH/idVendor
            echo "0x0104" > $USB_GADGET_PATH/idProduct
            echo "$STORAGE_DEVICE" > $USB_GADGET_PATH/functions/mass_storage.usb0/lun.0/file
            echo 1 > $USB_GADGET_PATH/functions/mass_storage.usb0/lun.0/removable
            mkdir -p $USB_GADGET_PATH/configs/c.1
            ln -s $USB_GADGET_PATH/functions/mass_storage.usb0 $USB_GADGET_PATH/configs/c.1/
            mkdir -p $USB_GADGET_PATH/strings/0x409
            echo "TrimUI" > $USB_GADGET_PATH/strings/0x409/manufacturer
            echo "TrimUI Device" > $USB_GADGET_PATH/strings/0x409/product
            echo "1234567890" > $USB_GADGET_PATH/strings/0x409/serialnumber
            echo "" > $USB_GADGET_PATH/UDC 2>/dev/null
            echo "musb-hdrc" > $USB_GADGET_PATH/UDC
            ;;
        "Flip")
            mkdir -p "$USB_GADGET_PATH/functions/mass_storage.0/lun.0" 2>/dev/null
            echo "1" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable" 2>/dev/null
            echo "0" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/ro" 2>/dev/null
            echo "$STORAGE_DEVICE" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
            [ -e "$USB_CONFIG_PATH/mass_storage.0" ] || ln -sf "$USB_GADGET_PATH/functions/mass_storage.0" "$USB_CONFIG_PATH/" 2>/dev/null
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            sleep 1
            echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            ;;
        "Pixel2")
            mkdir $USB_GADGET_PATH -m 0770
            echo "0x2207" > $USB_GADGET_PATH/idVendor
            echo "0x0000" > $USB_GADGET_PATH/idProduct
            echo "0x0200" > $USB_GADGET_PATH/bcdUSB
            mkdir $USB_GADGET_PATH/strings/0x409 -m 0770
            echo “0123456789ABCDEF” > $USB_GADGET_PATH/strings/0x409/serialnumber
            echo “GameKiddy” > $USB_GADGET_PATH/strings/0x409/manufacturer
            echo “Pixel2” > $USB_GADGET_PATH/strings/0x409/product
            mkdir $USB_CONFIG_PATH -m 0770
            mkdir $USB_CONFIG_PATH/strings/0x409 -m 0770
            echo "mass_storage" > $USB_CONFIG_PATH/strings/0x409/configuration
            mkdir $USB_GADGET_PATH/functions/mass_storage.0
            echo $STORAGE_DEVICE > $USB_GADGET_PATH/functions/mass_storage.0/lun.0/file
		    echo 1 > $USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable
		    echo 0 > $USB_GADGET_PATH/functions/mass_storage.0/lun.0/nofua
            ln -s $USB_GADGET_PATH/functions/mass_storage.0 $USB_GADGET_PATH/configs/b.1/mass_storage.0
            echo $USB_UDC_CONTROLLER > $USB_GADGET_PATH/UDC
            ;;
            "SmartProS")
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            mkdir -p "$USB_GADGET_PATH/functions/mass_storage.0"
            echo 1 > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable"
            echo 0 > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/ro"
            echo "$STORAGE_DEVICE" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file"
            mkdir -p "$USB_CONFIG_PATH/strings/0x409"
            echo "Mass Storage" > "$USB_CONFIG_PATH/strings/0x409/configuration"
            [ -L "$USB_CONFIG_PATH/mass_storage.0" ] || ln -s "$USB_GADGET_PATH/functions/mass_storage.0" "$USB_CONFIG_PATH/"
            sleep 1
            echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Card-less USB session (SPR-MED-198)
#
# The PC must never be handed a filesystem the kernel still has mounted. So
# USB Storage Mode is run as a shutdown that pauses before the power command:
# the app stages the shutdown UI (spruce/scripts/shutdown_ui.sh: display tool,
# input reader, fsck.fat, font, background, platform facts) plus this file
# into /tmp, hands over to save_poweroff.sh --usb-storage-export, stage 2 does
# its strict clean unmount, and then sources this file from /tmp and calls
# usb_session_run - repair if the dirty flag is set, export, static screen,
# wait for A or the cable, release, back to stage 2 for the reboot.
# Everything the session touches lives on the rootfs or in /tmp.
# ---------------------------------------------------------------------------
USB_SESSION_DIR="${USB_SESSION_DIR:-/tmp/usbstorage}"
SHUTDOWN_UI_DIR="${SHUTDOWN_UI_DIR:-/tmp/shutdown_ui}"

# Card side: stage the shutdown UI and this file. Returns 1 if anything is
# missing, in which case the caller keeps the mounted export.
usb_session_stage() {
    [ -f /mnt/SDCARD/spruce/scripts/shutdown_ui.sh ] || { log_message "USB Storage Mode: shutdown_ui.sh missing"; return 1; }
    . /mnt/SDCARD/spruce/scripts/shutdown_ui.sh
    shutdown_ui_stage || return 1
    rm -rf "$USB_SESSION_DIR"
    mkdir -p "$USB_SESSION_DIR" || return 1
    cp /mnt/SDCARD/App/USBStorageMode/usb_gadget.sh "$USB_SESSION_DIR/usb_gadget.sh" || return 1
    sync
    log_message "USB Storage Mode: session staged in $USB_SESSION_DIR"
    return 0
}

# Block until the cable is pulled or A is pressed. Prints which.
usb_session_wait_for_exit() {
    shutdown_ui_getevent_start
    _why=""
    while [ -z "$_why" ]; do
        if [ "$(cat "$BATTERY/status" 2>/dev/null)" = "Discharging" ]; then
            _why="cable disconnected"
        elif shutdown_ui_key_seen A; then
            _why="A pressed"
        else
            sleep 0.2
        fi
    done
    shutdown_ui_getevent_stop
    echo "$_why"
}

# Runs inside stage 2, after the strict unmount, from the /tmp copies.
usb_session_run() {
    [ -f "$SHUTDOWN_UI_DIR/shutdown_ui.sh" ] || { echo "usb session: no shutdown UI in $SHUTDOWN_UI_DIR"; return 1; }
    . "$SHUTDOWN_UI_DIR/shutdown_ui.sh"
    shutdown_ui_load_env || { echo "usb session: no env in $SHUTDOWN_UI_DIR"; return 1; }
    usb_gadget_platform_setup || { echo "usb session: no gadget table for $PLATFORM"; return 1; }
    # The whole point: refuse to export a mounted card.
    if grep -q "^$SD_DEV " /proc/mounts; then
        echo "usb session: $SD_DEV is still mounted, refusing to export"
        return 1
    fi
    # The FAT dirty flag is sticky (SPR-MED-199): a card cut once is offered
    # "scan and fix" on every insert until an fsck clears it. This is the one
    # moment the card is cleanly unmounted and quiesced, and the repair takes
    # seconds: run it, and only then export.
    _flag="$(sd_card_dirty_flag)"
    shutdown_ui_log "dirty flag after the device's unmount: $_flag"
    case "$_flag" in dirty*) sd_card_repair "Checking the SD card before USB mode..." ;; esac
    shutdown_ui_log "exporting $SD_DEV (unmounted)"
    usb_export_gadget
    shutdown_ui_display "USB Mode Active. Press A to exit and reboot your device."
    _why="$(usb_session_wait_for_exit)"
    shutdown_ui_log "exit ($_why)"
    shutdown_ui_display "Device will now reboot."
    usb_gadget_release
    sleep 1
    shutdown_ui_log "dirty flag after the PC gave the card back: $(sd_card_dirty_flag)"
    shutdown_ui_display_kill
    shutdown_ui_display_errors
    return 0
}
