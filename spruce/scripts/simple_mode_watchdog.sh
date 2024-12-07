#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

TOGGLE_SIMPLE="/mnt/SDCARD/spruce/scripts/applySetting/simple_mode.sh"

detect_konami_code() {

	log_message "listening for Konami Code"

	NUM_CORRECT=0

	/mnt/SDCARD/spruce/bin/getevent /dev/input/event3 | while read line; do

		log_message "number of correct inputs: $NUM_CORRECT"

		case "$line" in
			*"$B_UP 1"*)
				log_message "+++UP"
				if [ $NUM_CORRECT -eq 0 ] || [ $NUM_CORRECT -eq 1 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_DOWN 1"*)
				log_message "+++DOWN"
				if [ $NUM_CORRECT -eq 2 ] || [ $NUM_CORRECT -eq 3 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_LEFT 1"*)
				log_message "+++LEFT"
				if [ $NUM_CORRECT -eq 4 ] || [ $NUM_CORRECT -eq 6 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_RIGHT 1"*)
				log_message "+++RIGHT"
				if [ $NUM_CORRECT -eq 5 ] || [ $NUM_CORRECT -eq 7 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_B 1"*)
				log_message "+++B"
				if [ $NUM_CORRECT -eq 8 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_A 1"*)
				log_message "+++A"
				if [ $NUM_CORRECT -eq 9 ]; then
					NUM_CORRECT=$((NUM_CORRECT + 1))
				else
					NUM_CORRECT=0
				fi
				;;
			*"$B_START 1"*)
				log_message "+++START"
				if [ $NUM_CORRECT -eq 10 ]; then
					log_message "11 correct inputs in a row! removing simple_mode."
					"$TOGGLE_SIMPLE" remove
					break
				else
					NUM_CORRECT=0
				fi
				;;
			*0)
				log_message "---button released"
				;;

			*)
				log_message "-+-+- Some other button pressed!"
				NUM_CORRECT=0
				;;
		esac
	done
}

while true; do
	while flag_check "simple_mode" && pgrep "MainUI" > /dev/null; do
		log_message "simple_mode active and MainUI detected"
		detect_konami_code
		sleep 5
	done
	log_message "simple_mode OR MainUI not detected"
	sleep 5
done &
