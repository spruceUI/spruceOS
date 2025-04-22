#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

TOGGLE_SIMPLE="/mnt/SDCARD/spruce/scripts/applySetting/simple_mode.sh"
GETEVENT=/mnt/SDCARD/spruce/bin64/getevent
[ "$PLATFORM" = "A30" ] && GETEVENT=/mnt/SDCARD/spruce/bin/getevent

FIFO="/tmp/konami_fifo"
rm -f $FIFO 2>/dev/null
mkfifo $FIFO
log_message "simple_mode_watchdog.sh: created $FIFO"

detect_konami_code() {
	log_message "simple_mode_watchdog.sh: Started listening for Konami Code"
	
	# Start getevent in background, writing to the FIFO
	log_message "GETEVENT = $GETEVENT" -v
	log_message "EVENT_PATH_KEYBOARD = $EVENT_PATH_KEYBOARD" -v
	log_message "FIFO = $FIFO" -v
	$GETEVENT $EVENT_PATH_KEYBOARD > "$FIFO" &
	export konami_pid=$!
	log_message "konami_pid = $konami_pid" -v
	NUM_CORRECT=0
	
	while read line; do
		log_message "number of correct inputs: $NUM_CORRECT" -v
		
		case "$line" in
			*"$B_UP"*)
				log_message "+++UP" -v
				if [ $NUM_CORRECT -eq 0 ] || [ $NUM_CORRECT -eq 1 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_DOWN"*)
				log_message "+++DOWN" -v
				if [ $NUM_CORRECT -eq 2 ] || [ $NUM_CORRECT -eq 3 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_LEFT"*)
				log_message "+++LEFT" -v
				if [ $NUM_CORRECT -eq 4 ] || [ $NUM_CORRECT -eq 6 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_RIGHT"*)
				log_message "+++RIGHT" -v
				if [ $NUM_CORRECT -eq 5 ] || [ $NUM_CORRECT -eq 7 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_B 1"*)
				log_message "+++B" -v
				if [ $NUM_CORRECT -eq 8 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_A 1"*)
				log_message "+++A" -v
				if [ $NUM_CORRECT -eq 9 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_START 1"*)
				log_message "+++START" -v
				if [ $NUM_CORRECT -eq 10 ] && flag_check "in_menu"; then
					log_message "11 correct inputs in a row! removing simple_mode."
					"$TOGGLE_SIMPLE" remove
					# Kill getevent and clean up
					kill $konami_pid 2>/dev/null
					unset konami_pid 2>/dev/null
					rm -f "$FIFO"
					return 0
				else
					NUM_CORRECT=0
				fi
				;;
			*0)
				log_message "---button released" -v
				;;
			*)
				log_message "-+-+- Some other button pressed!" -v
				NUM_CORRECT=0
				;;
		esac
	done < "$FIFO"
	
	# Clean up if we exit the loop some other way
	kill $konami_pid 2>/dev/null
	unset konami_pid 2>/dev/null
	rm -f "$FIFO"
}

while true; do
	while flag_check "simple_mode" && flag_check "in_menu"; do
		log_message "simple_mode_watchdog.sh: simple_mode active and MainUI detected"
		
		[ -z "$konami_pid" ] && detect_konami_code
		sleep 5
	done
	log_message "simple_mode_watchdog.sh: simple_mode OR MainUI not detected" -v
	sleep 5
done