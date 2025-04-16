#!/bin/bash

# Path to the log file
LOG_FILE="/mnt/sdcard/Saves/spruce/port32.log"

# Check if the file exists
while true; do
	if [[ -f "$LOG_FILE" ]]; then
		echo "Searching for 'SIGSEGV' in $LOG_FILE..."

		# Capture the first matching line into a variable
		sigsegv_line=$(egrep "SIGSEGV|segfault" "$LOG_FILE" | head -n 1)

		# Check if a match was found
		if [[ -n "$sigsegv_line" ]]; then
			echo "Found SIGSEGV line:"
			echo "$sigsegv_line"

			# Run the ps command, filter for 'box86', and exclude the grep process itself
			pid=$(ps -f | grep "box86" | grep -v "grep" | awk 'NR==1 {print $1}')

			# Check if a PID was found
			if [[ -n "$pid" ]]; then
				echo "The first PID with 'box86' (excluding grep) is: $pid. Killing..."
				kill -9 $pid
				# exit 0
			else
				echo "No process with 'box86' found."
				exit 0
			fi
		else
			echo "No SIGSEGV found."
		fi
	else
		echo "Log file not found: $LOG_FILE"
		exit 1
	fi
	
	sleep 5
	
done