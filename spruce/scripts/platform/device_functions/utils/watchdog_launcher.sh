#!/bin/sh

launch_common_startup_watchdogs(){
    log_message "Launching common startup watchdogs v1"
    /mnt/SDCARD/spruce/scripts/powerbutton_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    /mnt/SDCARD/spruce/scripts/low_power_warning.sh &
    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}
    pin_cpu "$SYSTEM_CPU" -n powerbutton_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n idlemon_mm.sh &
    pin_cpu "$SYSTEM_CPU" -n low_power_warning.sh &
    pin_cpu "$SYSTEM_CPU" -n homebutton_watchdog.sh &
}

launch_common_startup_watchdogs_v2() {
    log_message "Launching common startup watchdogs v2"
    HAS_LID="${1:-false}" 

    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    /mnt/SDCARD/spruce/scripts/low_power_warning.sh &
    /mnt/SDCARD/spruce/scripts/power_button_watchdog_v2.sh &
    /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh &

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}
    pin_cpu "$SYSTEM_CPU" -n homebutton_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n idlemon_mm.sh &
    pin_cpu "$SYSTEM_CPU" -n low_power_warning.sh &
    pin_cpu "$SYSTEM_CPU" -n power_button_watchdog_v2.sh &
    pin_cpu "$SYSTEM_CPU" -n buttons_watchdog.sh &

    if [ "$HAS_LID" = "true" ]; then
        /mnt/SDCARD/spruce/scripts/lid_watchdog_v2.sh &
        pin_cpu "$SYSTEM_CPU" -n lid_watchdog_v2.sh &
    fi


}