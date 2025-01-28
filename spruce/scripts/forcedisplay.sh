#!/bin/sh

# update display setting after wakeup

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

enforce_enhance() {
    WAKEUP_COUNT_OLD=$(cat $BATTERY/power/wakeup_count)
    while [ 1 ]; do
        WAKEUP_COUNT_NEW=$(cat $BATTERY/power/wakeup_count)
        if [ $WAKEUP_COUNT_OLD != $WAKEUP_COUNT_NEW ] ; then
            WAKEUP_COUNT_OLD=$WAKEUP_COUNT_NEW
            ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
            echo "$ENHANCE_SETTINGS" > /sys/devices/virtual/disp/disp/attr/enhance
        fi
        sleep 1
    done
}

enforce_enhance &