#!/bin/sh

export RA_DIR
export EMU_DIR
export GAME
export OVR_DIR
export OVERRIDE

messages_file="/var/log/messages"
count=0
# keys used here are down, B, L2, R2... I don't remember which is which
key18=0
key20=0
key29=0
key108=0

while [ 1 ]; do
	last_line=$(tail -n 1 "$messages_file")
# check which of 4 buttons are pushed.
	case "$last_line" in
		*"key 1 18 1"*)
			key18=1
			;;
		*"key 1 20 1"*)
			key20=1
			;;
		*"key 1 29 1"*)
			key29=1
			;;
		*"key 1 108 1"*)
			key108=1
			;;
		*"key 1 18 0"*)
			key18=0
			;;
		*"key 1 20 0"*)
			key20=0
			;;
		*"key 1 29 0"*)
			key29=0
			;;
		*"key 1 108 0"*)
			key108=0
			;;
	esac
	
# count up number of monitored keys currently depressed
	count=$((key18 + key20 + key29 + key108))
	
# make sure count doesn't go beyond bounds for some reason.
	if [ $count -lt 0 ]; then
		count=0
	elif [ $count -gt 4 ]; then
		count=4
	fi

# if all 4 buttons pushed, do the thing.
	if [ $count -eq 4 ]; then
		killall -15 retroarch || killall -15 /mnt/SDCARD/RetroArch/retroarch || killall -15 ra32.miyoo || killall -15 /mnt/SDCARD/RetroArch/ra32.miyoo
		touch "/mnt/SDCARD/.tmp_update/flags/gs_activated"
		sleep 1 && break
	fi
done
