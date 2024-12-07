#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

MESSAGE_FILE="/tmp/log/messages"
TOGGLE_SIMPLE="/mnt/SDCARD/spruce/scripts/applySetting/simple_mode.sh"

detect_konami_code() {

	i=1
	SUM_CORRECT=0

	LAST_24="$(tail -n 24 $MESSAGE_FILE)"

	echo "$LAST_24" | while read line; do
		case "$line" in
			1|3) # press up
				if echo "$line" | grep -q "$B_UP 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			2|4) # release up
				if echo "$line" | grep -q "$B_UP 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			5|7) # press down
				if echo "$line" | grep -q "$B_DOWN 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			6|8) # release down
				if echo "$line" | grep -q "$B_DOWN 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			9|13) # press left
				if echo "$line" | grep -q "$B_LEFT 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			10|14) # release left
				if echo "$line" | grep -q "$B_LEFT 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			11|15) # press right
				if echo "$line" | grep -q "$B_RIGHT 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			12|16) # release right
				if echo "$line" | grep -q "$B_RIGHT 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			17) # press B
				if echo "$line" | grep -q "$B_B 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			18) # release B
				if echo "$line" | grep -q "$B_B 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			19) # press A
				if echo "$line" | grep -q "$B_A 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			20) # release A
				if echo "$line" | grep -q "$B_A 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			21) # press START
				if echo "$line" | grep -q "$B_START 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			22) # duplicate START press log entry
				if echo "$line" | grep -q "$B_START_2 1"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;

			23) # release START
				if echo "$line" | grep -q "$B_START 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
			24) # duplicate START release log entry
				if echo "$line" | grep -q "$B_START_2 0"; then
					SUM_CORRECT=$((SUM_CORRECT + 1))
				fi
				;;
		esac

		i=$((i + 1))
	done

	if [ $SUM_CORRECT -ge 24 ]; then
		"$TOGGLE_SIMPLE" remove
	fi
}

while true; do
	while flag_check "simple_mode" && pgrep "MainUI" > /dev/null; do
		detect_konami_code
		sleep 1
	done
	sleep 5
done &
