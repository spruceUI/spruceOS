#!/bin/sh

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

runifnecessary(){
    a=`ps | grep $1 | grep -v grep`
    if [ "$a" == "" ] ; then
        $2 &
    fi
}

detectThemeChange(){
    SYSTEM_JSON="/config/system.json"
    LAST_THEME_FILE="/tmp/.last_theme"

    # Get current theme
    CURRENT_THEME=$(awk -F'"' '/"theme":/ {print $4}' "$SYSTEM_JSON")
    log_message "Current theme: $CURRENT_THEME"

    # Check if last theme file exists
    if [ ! -f "$LAST_THEME_FILE" ]; then
        echo "$CURRENT_THEME" > "$LAST_THEME_FILE"
        /mnt/SDCARD/.tmp_update/scripts/iconfreshLite.sh
        return
    fi

    # Read last theme
    LAST_THEME=$(cat "$LAST_THEME_FILE")

    # Compare current theme with last theme
    if [ "$CURRENT_THEME" != "$LAST_THEME" ]; then
        log_message "Theme changed to $CURRENT_THEME"
        echo "$CURRENT_THEME" > "$LAST_THEME_FILE"
        /mnt/SDCARD/.tmp_update/scripts/iconfreshLite.sh
    fi
}

rm /mnt/SDCARD/.tmp_update/flags/.save_active
while [ 1 ]; do
    # create in menu flag
    touch /mnt/SDCARD/.tmp_update/flags/in_menu.lock

    runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon
    cd ${SYSTEM_PATH}/app/
    ./MainUI  &> /dev/null

    # remove in menu flag
    rm /mnt/SDCARD/.tmp_update/flags/in_menu.lock

    if [ -f /tmp/.cmdenc ] ; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ] ; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > /mnt/SDCARD/.tmp_update/flags/.lastgame
	    /tmp/cmd_to_run.sh  &> /dev/null
        rm /tmp/cmd_to_run.sh

        detectThemeChange

        # some emulators may use 2 or more cores
        # therefore after closing an emulator
        # we need to turn off other cores except cpu0
        echo 1 > /sys/devices/system/cpu/cpu0/online 
        echo 0 > /sys/devices/system/cpu/cpu1/online 
        echo 0 > /sys/devices/system/cpu/cpu2/online 
        echo 0 > /sys/devices/system/cpu/cpu3/online 

        # sleep 1

        # show closing screen 
        /mnt/SDCARD/.tmp_update/scripts/select.sh  &> /dev/null
    fi
done
