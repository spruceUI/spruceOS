#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
GOVERNOR_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
sleep 10
governor="$(cat "$GOVERNOR_FILE")"
if [ "$governor" != "conservative" ]; then
	# lock menu button to prevent ra32 menu from changing governor before we can lock out its write permission
	killall -19 getevent
	log_message "CPU governor is not set to conservative. Re-enforcing SMART mode"
	set_smart "$1"
	# re-enable menu button now that ra32 can't reset the governor
	killall -18 getevent 
fi