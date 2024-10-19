#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Function to set system time using NTP
set_system_time() {
	ntpd -n -q -p "$1"
}

if ifconfig wlan0 | grep -qE "inet |inet6 " && flag_check "enableNetworkTimeSync" > /dev/null; then

	# Try to set the time using pool.ntp.org, fallback to time.google.com
	set_system_time "pool.ntp.org" || set_system_time "time.google.com"

	response=$(curl -s "http://ip-api.com/json/?fields=status,timezone,offset")

	# Parse the status, timezone, and offset fields
	status=$(echo "$response" | grep '"status"' | sed 's/.*"status":"\([^"]*\)".*/\1/')
	timezone=$(echo "$response" | grep '"timezone"' | sed 's/.*"timezone":"\([^"]*\)".*/\1/')
	offset_seconds=$(echo "$response" | grep '"offset"' | sed 's/.*"offset":\([0-9-]*\).*/\1/')

	# Check if the response is successful
	if [ "$status" = "success" ]; then
		# Calculate the offset in hours for POSIX format
		offset_hours=$((offset_seconds / 3600))

		# Set the TZ environment variable in the POSIX format
		if [ "$offset_hours" -lt 0 ]; then
			export TZ="UTC$offset_hours"
		else
			export TZ="UTC+$offset_hours"
		fi

		current_time_seconds=$(date -u "+%s")
		local_time_seconds=$((current_time_seconds + offset_seconds))
		log_message "Syncing System Time & RTC to Network..."
		date -u -s "@$local_time_seconds"
		hwclock -w
	fi

fi