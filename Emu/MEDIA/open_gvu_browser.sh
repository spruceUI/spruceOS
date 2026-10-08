#!/bin/sh
export OPEN_GVU_BROWSER=true
killall -q menubutton_watchdog.sh
/mnt/SDCARD/Emu/MEDIA/../../spruce/scripts/emu/standard_launch.sh "$@"
/mnt/SDCARD/spruce/scripts/menubutton_watchdog.sh &
