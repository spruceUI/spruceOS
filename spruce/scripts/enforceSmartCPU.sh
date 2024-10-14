#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
set_smart # this should be the starting point before trying to detect a change
GOVERNOR_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
while true; do
    /mnt/SDCARD/.tmp_update/bin/inotify.elf "$GOVERNOR_FILE"
	governor="$(cat "$GOVERNOR_FILE")"
    if [ "$governor" != "conservative" ]; then
		log_message "CPU governor has changed. Re-enforcing SMART mode"
		set_smart
    fi
done
