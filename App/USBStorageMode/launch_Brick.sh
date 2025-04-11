#!/bin/sh

DIR=$(dirname "$0")
cd "$DIR"

USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
USB_POWER_PATH="/sys/class/power_supply/axp2202-usb"

check_sd_activity() {
    local prev_ios=$(awk '/mmcblk1p1/ {print $10}' /proc/diskstats)
    sleep 1
    local curr_ios=$(awk '/mmcblk1p1/ {print $10}' /proc/diskstats)
    
    if [ "$curr_ios" != "$prev_ios" ]; then
        return 1
    fi
    return 0
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
    mount /dev/mmcblk1p1 /mnt/SDCARD
    sync
}

setup_usb() {
    while true; do
        cable_status=$(cat $USB_POWER_PATH/present)
        
        if [ "$cable_status" = "0" ]; then
            ./show_message_Brick "Connect USB Cable" -l ab -a "OK" -b "CANCEL"
            button_result=$?
            
            if [ $button_result = 2 ]; then
                exit 0
            elif [ $button_result = 0 ]; then
                continue
            fi
        elif [ "$cable_status" = "1" ]; then
            break
        fi
        sleep 1
    done

    ./show_message_Brick "Enter USB Mass Storage Mode?" -l ab -a "OK" -b "CANCEL"
    if [ $? = 2 ]; then
        exit 0
    fi

    cable_status=$(cat $USB_POWER_PATH/present)
    if [ "$cable_status" = "0" ]; then
        ./show_message_Brick "USB Cable Disconnected" -l a -a "OK"
        sleep 2
        exit 0
    fi

    ./show_message_Brick "Connecting USB Mass Storage Mode" &

    
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
    umount -f /mnt/SDCARD
    echo "musb-hdrc" > $USB_GADGET_PATH/UDC
    killall show_message_Brick

    while true; do
        if [ "$(cat $USB_POWER_PATH/online)" = "0" ]; then
            ./show_message_Brick "USB Cable Disconnected" -l a -a "OK"
            cleanup_usb_gadget
            reboot
            exit 0
        fi

        ./show_message_Brick "USB Mass Storage Mode" -l a -a "Exit & Reboot"
        if [ $? = 0 ]; then
            if check_sd_activity; then
                cleanup_usb_gadget
                reboot
                exit 0
            else
                ./show_message_Brick "Data transfer in progress..." -l a -a "OK"
                continue
            fi
        fi
        sleep 1
    done
}

setup_usb