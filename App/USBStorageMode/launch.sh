#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

# --- Platform-specific configuration ---
case "$PLATFORM" in
    "A30")
        STORAGE_DEVICE="/dev/mmcblk0p1"
        MOUNT_POINT="/mnt/SDCARD"
        USB_GADGET_PATH="/sys/devices/platform/sunxi_usb_udc/gadget"
        LUN_PATH="$GADGET_PATH/lun0"
        LUN_FILE="$LUN_PATH/file"
        ;;
    "Brick" | "SmartPro")
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
        MOUNT_POINT="/storage/games-external"
        USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
        USB_UDC_CONTROLLER="ff300000.usb"
        USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"
        ;;
    *)
        # This will run if PyUI isn't ready yet, providing a basic message.
        /mnt/SDCARD/App/PyUI/main-ui/devices/utils/display_text "USB Storage Mode is not supported on this device." &
        sleep 3
        exit 1
        ;;
esac

# --- Unified Functions ---

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

remount_all() {
    mount -o rw "$STORAGE_DEVICE" "$MOUNT_POINT" 2>/dev/null
    if [ "$PLATFORM" = "A30" ]; then
        for mpoint in "/usr/miyoo/lib" "/tmp/lib" "/etc/profile" "/usr/miyoo/res" "/etc/group" "/etc/passwd"; do
            mount "$STORAGE_DEVICE" "$mpoint" 2>/dev/null
        done
    fi
    sync
}

cleanup_usb_gadget() {
    log_message "Cleaning up USB gadget..."
    sync
    echo 3 > /proc/sys/vm/drop_caches

    case "$PLATFORM" in
        "A30")
            echo "" > "$LUN_FILE" 2>/dev/null
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            ;;
        "Brick" | "SmartPro")
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
    esac

    sync
    echo 3 > /proc/sys/vm/drop_caches
    safe_unmount_all
    remount_all
    sync
}

configure_usb_gadget() {
    log_message "Configuring USB gadget for $PLATFORM..."
    safe_unmount_all
    sync
    echo 3 > /proc/sys/vm/drop_caches

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
        "Brick" | "SmartPro")
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
            echo "0x2207" > $USB_GADGET_PATH/rockchip/idVendor
            echo "0x0000" > $USB_GADGET_PATH/rockchip/idProduct
            echo "0x0200" > $USB_GADGET_PATH/rockchip/bcdUSB
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
    esac
}

# --- Main Execution ---

start_pyui_message_writer "1" # Wait for listener

# Warm up the display driver, mimicking other known-good apps
log_and_display_message "Loading..."
sleep 0.5 

# 1. Wait for USB cable connection, using the reliable charging status check
while [ "$(device_get_charging_status)" = "Discharging" ]; do
    log_and_display_message "Please connect the USB cable to your computer. Press A to check again, or B to cancel."
    if confirm; then
        # Loop will re-check charging status
        :
    else
        # User pressed B
        log_and_display_message "Cancelled by user."
        sleep 1
        exit 0
    fi
done

# 2. Confirm entry into USB mode
log_and_display_message "Enter USB Mass Storage Mode?\nPress A to confirm, or B to cancel."
if confirm; then
    # User pressed A, continue
    :
else
    # User pressed B
    log_and_display_message "Cancelled by user."
    sleep 1
    exit 0
fi

# 3. Double-check connection and start
if [ "$(device_get_charging_status)" = "Discharging" ]; then
    log_and_display_message "USB Cable Disconnected."
    sleep 2
    exit 0
fi

log_and_display_message "Connecting USB Mass Storage Mode..."
configure_usb_gadget
log_and_display_message "" # Clear the "Connecting" message

# 4. Main loop
while true; do
    if [ "$(device_get_charging_status)" = "Discharging" ]; then
        log_and_display_message "USB Cable Disconnected."
        cleanup_usb_gadget
        log_and_display_message "Device will now reboot."
        sleep 3
        reboot
        exit 0
    fi

    log_and_display_message "USB Mode Active.\nPress A to exit and reboot your device."
    if confirm; then
        cleanup_usb_gadget
        log_and_display_message "Device will now reboot."
        sleep 3
        reboot
        exit 0
    fi
    # Add a small sleep to prevent the loop from overwhelming the CPU
    sleep 1
done

exit 0