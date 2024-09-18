#!/bin/sh
messages_file="/var/log/messages"
last_line=$(tail "$messages_file")
case "$last_line" in
    *"turn on lcd"*)
	killall -9 display
	killall -18 retroarch
	killall -18 ra32.miyoo
	killall -18 dino_jump
	killall -18 MainUI
	killall -18 drastic
	echo "pulsacion"
	exit 0
	break
        ;;        
	*)
	killall -9 display
	killall -19 retroarch
	killall -19 ra32.miyoo
	killall -19 dino_jump	
	killall -19 MainUI
	killall -19 drastic
	echo 225 > /sys/devices/virtual/timed_output/vibrator/enable
	killall keymon &&
	display /mnt/SDCARD/.tmp_update/res/deep.png &
	echo "por tiempo"
	sleep 4
	echo bootfast > /sys/power/state
	killall -9 display
	echo "volvemos"
	keymon &
	killall -18 retroarch
	killall -18 ra32.miyoo
	killall -18 drastic
	killall -18 dino_jump
	killall -18 MainUI
	exit 0
	break
	;;	       
esac
