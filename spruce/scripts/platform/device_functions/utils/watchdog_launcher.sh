#!/bin/sh

launch_common_startup_watchdogs(){
    /mnt/SDCARD/spruce/scripts/powerbutton_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    /mnt/SDCARD/spruce/scripts/low_power_warning.sh &
    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &
}