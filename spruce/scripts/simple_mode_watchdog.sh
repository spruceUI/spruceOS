#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

TOGGLE_SIMPLE="/mnt/SDCARD/spruce/scripts/applySetting/simple_mode.sh"

detect_konami_code() {
	log_message "listening for Konami Code"
	
	FIFO="/tmp/konami_fifo"
	rm -f "$FIFO"
	mkfifo "$FIFO"
	
	# Start getevent in background, writing to the FIFO
	/mnt/SDCARD/spruce/bin/getevent /dev/input/event3 > "$FIFO" &
	getevent_pid=$!
	
	NUM_CORRECT=0
	
	while read line; do
		log_message "number of correct inputs: $NUM_CORRECT" -v
		
		case "$line" in
			*"key $B_UP"*)
				log_message "+++UP" -v
				if [ $NUM_CORRECT -eq 0 ] || [ $NUM_CORRECT -eq 1 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"key $B_DOWN"*)
				log_message "+++DOWN" -v
				if [ $NUM_CORRECT -eq 2 ] || [ $NUM_CORRECT -eq 3 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"key $B_LEFT"*)
				log_message "+++LEFT" -v
				if [ $NUM_CORRECT -eq 4 ] || [ $NUM_CORRECT -eq 6 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"key $B_RIGHT"*)
				log_message "+++RIGHT" -v
				if [ $NUM_CORRECT -eq 5 ] || [ $NUM_CORRECT -eq 7 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"key $B_B 1"*)
				log_message "+++B" -v
				if [ $NUM_CORRECT -eq 8 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"key $B_A 1"*)
				log_message "+++A" -v
				if [ $NUM_CORRECT -eq 9 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"key $B_START 1"*)
				log_message "+++START" -v
				if [ $NUM_CORRECT -eq 10 ]; then
					log_message "11 correct inputs in a row! removing simple_mode."
					"$TOGGLE_SIMPLE" remove
					# Kill getevent and clean up
					kill $getevent_pid
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
	kill $getevent_pid 2>/dev/null
	rm -f "$FIFO"
}

while true; do
	while flag_check "simple_mode" && flag_check "in_menu"; do
		log_message "simple_mode active and MainUI detected"
		
		detect_konami_code
		sleep 5
	done
	log_message "simple_mode OR MainUI not detected" -v
	sleep 5
done