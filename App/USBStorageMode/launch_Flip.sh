#!/bin/sh
DIR=$(dirname "$0")
cd "$DIR"

STORAGE_DEVICE="/dev/mmcblk1p1"
MOUNT_POINT="/mnt/SDCARD"
AC_POWER_PATH="/sys/class/power_supply/ac"
USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
USB_UDC_CONTROLLER="fcc00000.dwc3"
USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"

check_usb_connection() {
    if [ -f "$AC_POWER_PATH/online" ]; then
        ac_online=$(cat "$AC_POWER_PATH/online" 2>/dev/null || echo "0")
        [ "$ac_online" = "1" ] && return 0
    fi
    return 1
}

check_sd_activity() {
    local prev_ios=$(awk '/mmcblk1p1/ {print $10}' /proc/diskstats 2>/dev/null || echo "0")
    sleep 1
    local curr_ios=$(awk '/mmcblk1p1/ {print $10}' /proc/diskstats 2>/dev/null || echo "0")
    [ "$curr_ios" = "$prev_ios" ]
}

safe_umount() {
    for i in 1 2 3 4 5; do
        if ! grep -q "$MOUNT_POINT" /proc/mounts; then
            break
        fi
        sync
        umount "$MOUNT_POINT" 2>/dev/null && break
        sleep 1
    done
    if grep -q "$MOUNT_POINT" /proc/mounts; then
        umount -f "$MOUNT_POINT" 2>/dev/null
    fi
}

cleanup_usb_gadget() {
    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null
    sleep 1
    echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
    echo "" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
    rm -f "$USB_CONFIG_PATH/mass_storage.0" 2>/dev/null
    safe_umount
    mount -o rw "$STORAGE_DEVICE" "$MOUNT_POINT" 2>/dev/null
    sync
    echo 3 > /proc/sys/vm/drop_caches
}

setup_usb() {
    while true; do
        if check_usb_connection; then
            break
        else
            ./show_message "Connect USB Cable" -l ab -a "OK" -b "CANCEL"
            button_result=$?
            [ $button_result -eq 2 ] && exit 0
            [ $button_result -eq 0 ] && continue
        fi
        sleep 1
    done

    ./show_message "Enter USB Mass Storage Mode?" -l ab -a "OK" -b "CANCEL"
    [ $? -eq 2 ] && exit 0

    if ! check_usb_connection; then
        ./show_message "USB Cable Disconnected" -l a -a "OK"
        sleep 2
        exit 0
    fi

    ./show_message "Connecting USB Mass Storage Mode" &
    notif_pid=$!

    mkdir -p "$USB_GADGET_PATH/functions/mass_storage.0/lun.0" 2>/dev/null
    echo "1" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable" 2>/dev/null
    echo "0" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/ro" 2>/dev/null
    echo "$STORAGE_DEVICE" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null

    if [ -e "$USB_CONFIG_PATH/mass_storage.0" ]; then
        rm -f "$USB_CONFIG_PATH/mass_storage.0" 2>/dev/null
    fi
    ln -sf "$USB_GADGET_PATH/functions/mass_storage.0" "$USB_CONFIG_PATH/" 2>/dev/null

    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
    sleep 1

    echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null
    sleep 1
    echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
    sleep 1
    echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null

    kill $notif_pid 2>/dev/null

    while true; do
        if ! check_usb_connection; then
            ./show_message "USB Cable Disconnected" -l a -a "OK"
            cleanup_usb_gadget
            reboot
            exit 0
        fi

        ./show_message "USB Mass Storage Mode" -l a -a "Exit & Reboot"
        if [ $? -eq 0 ]; then
            if check_sd_activity; then
                cleanup_usb_gadget
                reboot
                exit 0
            else
                ./show_message "Data transfer in progress..." -l a -a "OK"
                continue
            fi
        fi

        sleep 1
    done
}

setup_usb
