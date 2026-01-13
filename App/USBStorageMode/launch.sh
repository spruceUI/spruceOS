#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# --- Platform-specific configuration ---
case "$PLATFORM" in
    "A30")
        STORAGE_DEVICE="/dev/mmcblk0p1"
        MOUNT_POINT="/mnt/SDCARD"
        USB_POWER_PATH="/sys/class/power_supply/usb"
        GADGET_PATH="/sys/devices/platform/sunxi_usb_udc/gadget"
        LUN_PATH="$GADGET_PATH/lun0"
        LUN_FILE="$LUN_PATH/file"
        ;;
    "Brick" | "SmartPro")
        STORAGE_DEVICE="/dev/mmcblk1p1"
        MOUNT_POINT="/mnt/SDCARD"
        USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
        USB_POWER_PATH="/sys/class/power_supply/axp2202-usb"
        ;;
    "Flip")
        STORAGE_DEVICE="/dev/mmcblk1p1"
        MOUNT_POINT="/mnt/SDCARD"
        USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
        USB_UDC_CONTROLLER="fcc00000.dwc3"
        USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"
        UDC_STATE_FILE="/sys/class/udc/fcc00000.dwc3/state"
        ;;
    *)
        log_and_display_message "USB Storage Mode is not supported on this device."
        sleep 3
        exit 1
        ;;
esac

# --- Unified Functions ---

# Displays a prompt and waits for A (OK) or B/START (Cancel).
# Returns 0 for OK, 1 for Cancel.
display_blocking_prompt() {
    local message="$1"
    local ok_text="$2"
    local cancel_text="$3"
    local full_message
    
    # Construct a single-line message
    if [ -n "$cancel_text" ]; then
        full_message=$(printf "%s (A: %s / B: %s)" "$message" "$ok_text" "$cancel_text")
    else
        full_message=$(printf "%s (A: %s)" "$message" "$ok_text")
    fi
    log_and_display_message "$full_message"

    # Wait for A, B, or START button press
    while true; do
        button=$(get_button_press 300) # 5-minute timeout
        # Always exit on A
        if [ "$button" = "A" ]; then
            log_and_display_message "" # Clear prompt
            return 0
        fi
        # Only exit on B/START if a cancel option was provided
        if [ -n "$cancel_text" ]; then
            if [ "$button" = "B" ] || [ "$button" = "START" ]; then
                log_and_display_message "" # Clear prompt
                return 1
            fi
        fi
        # For all other buttons, or for B/START on single-option
        # prompts, the loop continues and waits for a valid button press.
    done
}

check_usb_connection() {
    case "$PLATFORM" in
        "A30" | "Brick" | "SmartPro")
            for status_file in "$USB_POWER_PATH/present" "$USB_POWER_PATH/online"; do
                if [ -f "$status_file" ] && [ "$(cat "$status_file" 2>/dev/null)" = "1" ]; then
                    return 0
                fi
            done
            ;;
        "Flip")
            [ "$(cat "$UDC_STATE_FILE" 2>/dev/null)" = "configured" ] && return 0
            ;;
    esac
    return 1
}

check_sd_activity() {
    local device_name=$(basename "$STORAGE_DEVICE")
    local prev_ios=$(awk -v dev="$device_name" '$3 == dev {print $10}' /proc/diskstats 2>/dev/null || echo "0")
    sleep 1
    local curr_ios=$(awk -v dev="$device_name" '$3 == dev {print $10}' /proc/diskstats 2>/dev/null || echo "0")
    [ "$curr_ios" = "$prev_ios" ]
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
        "Flip")
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
    esac
}

# --- Main Execution ---

start_pyui_message_writer "1" # Wait for listener

# 1. Wait for USB cable
while ! check_usb_connection; do
    display_blocking_prompt "USB Connection: Please connect the USB cable to your computer." "OK" "Cancel"
    if [ $? -ne 0 ]; then
        log_and_display_message "Cancelled by user."
        sleep 1
        exit 0
    fi
done

# 2. Confirm entry
display_blocking_prompt "USB Storage Mode: Do you want to enter USB Mass Storage Mode?" "Enter" "Cancel"
if [ $? -ne 0 ]; then
    log_and_display_message "Cancelled by user."
    sleep 1
    exit 0
fi

# 3. Double-check connection and start
if ! check_usb_connection; then
    log_and_display_message "USB Cable Disconnected."
    sleep 2
    exit 0
fi

log_and_display_message "Connecting USB Mass Storage Mode..."
configure_usb_gadget
log_and_display_message "" # Clear the "Connecting" message

# 4. Main loop
while true; do
    if ! check_usb_connection; then
        log_and_display_message "USB Cable Disconnected."
        cleanup_usb_gadget
        log_and_display_message "Device will now reboot."
        sleep 3
        reboot
        exit 0
    fi

    display_blocking_prompt "USB Mass Storage Mode: The device is in USB mode. Do not unplug without exiting first." "Exit & Reboot"
    
    if [ $? -eq 0 ]; then # "Exit & Reboot" was pressed
        cleanup_usb_gadget
        log_and_display_message "Device will now reboot."
        sleep 3
        reboot
        exit 0
    fi
    sleep 1
done

exit 0