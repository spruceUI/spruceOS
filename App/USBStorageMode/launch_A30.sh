#!/bin/sh
DIR=$(dirname "$0")
cd "$DIR"

STORAGE_DEVICE="/dev/mmcblk0p1"
MOUNT_POINT="/mnt/SDCARD"
USB_POWER_PATH="/sys/class/power_supply/usb"
GADGET_PATH="/sys/devices/platform/sunxi_usb_udc/gadget"
LUN_PATH="$GADGET_PATH/lun0"
LUN_FILE="$LUN_PATH/file"

check_sd_activity() {
    local prev_ios=$(awk '/mmcblk0p1/ {print $10}' /proc/diskstats)
    sleep 1
    local curr_ios=$(awk '/mmcblk0p1/ {print $10}' /proc/diskstats)
    
    if [ "$curr_ios" != "$prev_ios" ]; then
        return 1
    fi
    return 0
}

cleanup_usb_gadget() {
    echo "" > $LUN_FILE 2>/dev/null
    
    if [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ]; then
        echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
    fi
    
    sync
    echo 3 > /proc/sys/vm/drop_caches
    
    mount $STORAGE_DEVICE $MOUNT_POINT 2>/dev/null
    
    for mpoint in "/usr/miyoo/lib" "/tmp/lib" "/etc/profile" "/usr/miyoo/res" "/etc/group" "/etc/passwd"; do
        mount $STORAGE_DEVICE $mpoint 2>/dev/null
    done
    
    sync
}

setup_usb() {
    while true; do
        cable_status="0"
        for status_file in "$USB_POWER_PATH/present" "$USB_POWER_PATH/online"; do
            if [ -f "$status_file" ]; then
                cable_status=$(cat $status_file 2>/dev/null || echo "0")
                if [ "$cable_status" = "1" ]; then
                    break
                fi
            fi
        done
        
        if [ "$cable_status" = "0" ]; then
            $DIR/show_message_A30 "Connect USB Cable" -l ab -a "OK" -b "CANCEL"
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
    
    $DIR/show_message_A30 "Enter USB Mass Storage Mode?" -l ab -a "OK" -b "CANCEL"
    confirm_result=$?
    
    if [ $confirm_result = 2 ]; then
        exit 0
    fi
    
    cable_status="0"
    for status_file in "$USB_POWER_PATH/present" "$USB_POWER_PATH/online"; do
        if [ -f "$status_file" ]; then
            cable_status=$(cat $status_file 2>/dev/null || echo "0")
            if [ "$cable_status" = "1" ]; then
                break
            fi
        fi
    done
    
    if [ "$cable_status" = "0" ]; then
        $DIR/show_message_A30 "USB Cable Disconnected" -l a -a "OK"
        sleep 2
        exit 0
    fi
    
    $DIR/show_message_A30 "Connecting USB Mass Storage Mode" &
    notification_pid=$!
    
    sync
    echo 3 > /proc/sys/vm/drop_caches
    
    for mpoint in $(mount | grep $STORAGE_DEVICE | awk '{print $3}' | sort -r); do
        umount -f $mpoint 2>/dev/null || umount -l $mpoint 2>/dev/null
    done
    
    echo "" > $LUN_FILE 2>/dev/null
    if [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ]; then
        echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
    fi
    sleep 1
    
    if [ -f "$LUN_PATH/ro" ]; then
        echo 0 > $LUN_PATH/ro 2>/dev/null
    fi
    
    if [ -f "$LUN_PATH/nofua" ]; then
        echo 0 > $LUN_PATH/nofua 2>/dev/null
    fi
    
    if [ -f "$LUN_PATH/removable" ]; then
        echo 1 > $LUN_PATH/removable 2>/dev/null
    fi
    
    echo $STORAGE_DEVICE > $LUN_FILE 2>/dev/null
    sleep 1
    
    if [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ]; then
        echo 1 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
    fi
    
    ANDROID_USB="/sys/class/android_usb/android0"
    if [ -d "$ANDROID_USB" ]; then
        if [ -f "$ANDROID_USB/enable" ]; then
            echo 0 > $ANDROID_USB/enable 2>/dev/null
            sleep 1
        fi
        
        if [ -f "$ANDROID_USB/functions" ]; then
            echo "mass_storage" > $ANDROID_USB/functions 2>/dev/null
        fi
        
        for lun in $(find $ANDROID_USB -name "*lun*file" 2>/dev/null); do
            echo $STORAGE_DEVICE > $lun 2>/dev/null
        done
        
        if [ -f "$ANDROID_USB/enable" ]; then
            echo 1 > $ANDROID_USB/enable 2>/dev/null
        fi
    fi
    
    kill $notification_pid 2>/dev/null
    
    while true; do
        online_status="0"
        for status_file in "$USB_POWER_PATH/present" "$USB_POWER_PATH/online"; do
            if [ -f "$status_file" ]; then
                online_status=$(cat $status_file 2>/dev/null || echo "0")
                if [ "$online_status" = "1" ]; then
                    break
                fi
            fi
        done
        
        if [ "$online_status" = "0" ]; then
            $DIR/show_message_A30 "USB Cable Disconnected" -l a -a "OK"
            cleanup_usb_gadget
            $DIR/show_message_A30 "Device will power off|You'll need to turn it on again" -l a -a "OK"
            sleep 2
            reboot
            exit 0
        fi
        
        $DIR/show_message_A30 "USB Mass Storage Mode" -l a -a "Exit & Power Off"
        exit_choice=$?
        
        if [ $exit_choice = 0 ]; then
            if check_sd_activity; then
                cleanup_usb_gadget
                $DIR/show_message_A30 "Device will power off|You'll need to turn it on again" -l a -a "OK"
                sleep 2
                reboot
                exit 0
            else
                $DIR/show_message_A30 "Data transfer in progress..." -l a -a "OK"
                continue
            fi
        fi
        
        sleep 1
    done
}

setup_usb