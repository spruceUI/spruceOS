#!/bin/sh
DIR=$(dirname "$0")
cd "$DIR"
USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
USB_POWER_PATH="/sys/class/power_supply/axp2202-usb"

check_sd_activity() {
    local prev_ios=$(awk '/mmcblk1p1/ {print $10}' /proc/diskstats)
    sleep 1
    local curr_ios=$(awk '/mmcblk1p1/ {print $10}' /proc/diskstats)
    [ "$curr_ios" = "$prev_ios" ]
}

safe_umount() {
    for i in 1 2 3 4 5; do
        if ! grep -q '/mnt/SDCARD' /proc/mounts; then
            break
        fi
        sync
        umount /mnt/SDCARD 2>/dev/null && break
        sleep 1
    done
    if grep -q '/mnt/SDCARD' /proc/mounts; then
        umount -f /mnt/SDCARD 2>/dev/null
    fi
}

cleanup_usb_gadget() {
    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo "" > $USB_GADGET_PATH/UDC 2>/dev/null
    rm -f $USB_GADGET_PATH/configs/c.1/mass_storage.usb0
    rmdir $USB_GADGET_PATH/configs/c.1
    rmdir $USB_GADGET_PATH/functions/mass_storage.usb0
    rmdir $USB_GADGET_PATH/strings/0x409
    sync
    echo 3 > /proc/sys/vm/drop_caches
    safe_umount
    mount /dev/mmcblk1p1 /mnt/SDCARD
    sync
}

setup_usb() {
    while true; do
        cable_status=$(cat $USB_POWER_PATH/present)
        if [ "$cable_status" = "0" ]; then
            ./show_message "Connect USB Cable" -l ab -a "OK" -b "CANCEL"
            button_result=$?
            [ $button_result -eq 2 ] && exit 0
            [ $button_result -eq 0 ] && continue
        elif [ "$cable_status" = "1" ]; then
            break
        fi
        sleep 1
    done
    ./show_message "Enter USB Mass Storage Mode?" -l ab -a "OK" -b "CANCEL"
    [ $? -eq 2 ] && exit 0
    cable_status=$(cat $USB_POWER_PATH/present)
    if [ "$cable_status" = "0" ]; then
        ./show_message "USB Cable Disconnected" -l a -a "OK"
        sleep 2
        exit 0
    fi
    ./show_message "Connecting USB Mass Storage Mode" &
    mkdir -p $USB_GADGET_PATH/functions/mass_storage.usb0
    echo "0x1d6b" > $USB_GADGET_PATH/idVendor
    echo "0x0104" > $USB_GADGET_PATH/idProduct
    echo /dev/mmcblk1p1 > $USB_GADGET_PATH/functions/mass_storage.usb0/lun.0/file
    echo 1 > $USB_GADGET_PATH/functions/mass_storage.usb0/lun.0/removable
    mkdir -p $USB_GADGET_PATH/configs/c.1
    ln -s $USB_GADGET_PATH/functions/mass_storage.usb0 $USB_GADGET_PATH/configs/c.1/
    mkdir -p $USB_GADGET_PATH/strings/0x409
    echo "TrimUI" > $USB_GADGET_PATH/strings/0x409/manufacturer
    echo "TrimUI Device" > $USB_GADGET_PATH/strings/0x409/product
    echo "1234567890" > $USB_GADGET_PATH/strings/0x409/serialnumber
    echo "" > $USB_GADGET_PATH/UDC 2>/dev/null
    sync
    echo 3 > /proc/sys/vm/drop_caches
    safe_umount
    echo "musb-hdrc" > $USB_GADGET_PATH/UDC
    killall show_message
    while true; do
        if [ "$(cat $USB_POWER_PATH/online)" = "0" ]; then
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
