#!/bin/sh

# update display setting after wakeup

enforce_enhance() {
    WAKEUP_COUNT_OLD=$(cat /sys/class/power_supply/battery/power/wakeup_count)
    while [ 1 ]; do
        WAKEUP_COUNT_NEW=$(cat /sys/class/power_supply/battery/power/wakeup_count)
        if [ $WAKEUP_COUNT_OLD != $WAKEUP_COUNT_NEW ] ; then
            WAKEUP_COUNT_OLD=$WAKEUP_COUNT_NEW
            ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
            echo "$ENHANCE_SETTINGS" > /sys/devices/virtual/disp/disp/attr/enhance
        fi
        sleep 1
    done
}

enforce_enhance &