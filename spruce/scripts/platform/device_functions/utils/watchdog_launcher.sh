#!/bin/sh

launch_common_startup_watchdogs(){
    log_message "Launching common startup watchdogs v1"
    /mnt/SDCARD/spruce/scripts/powerbutton_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    /mnt/SDCARD/spruce/scripts/low_power_warning.sh &
    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &
}

launch_common_startup_watchdogs_v2() {
    log_message "Launching common startup watchdogs v2"
    HAS_LID="${1:-false}" 

    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    /mnt/SDCARD/spruce/scripts/low_power_warning.sh &
    /mnt/SDCARD/spruce/scripts/power_button_watchdog_v2.sh &
    /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh &

    if [ "$HAS_LID" = "true" ]; then
        /mnt/SDCARD/spruce/scripts/lid_watchdog_v2.sh &
    fi
}