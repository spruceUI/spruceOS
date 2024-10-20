#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

kill_current_process() {
    pid=$(ps | grep cmd_to_run | grep -v grep | sed 's/[ ]\+/ /g' | cut -d' ' -f2)
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    if [ "" != "$ppid" ]; then
        kill -9 $ppid
    fi
}

# ask for user response if MainUI is running
if flag_check "in_menu" ; then
    messages_file="/var/log/messages"
	# pause MainUI
	killall -q -19 MainUI
	# show notification screen
	display --text "Are you sure you want to shutdown?
 A-Confirm B-Cancel" --image "/mnt/SDCARD/spruce/imgs/bg_tree.png"
	# wait for button input
    while true; do
		# wait for log message update
        inotifywait "$messages_file"
		# get the last line of log file
        last_line=$(tail -n 1 "$messages_file")
        case "$last_line" in
			# B button - cancel shutdown
			*"key 1 29"*)
				# dismiss notification screen
				display_kill
				# resume Mainui
				killall -q -18 MainUI
				# exit script
				return 0
				break
				;;
			# A button - confirm shutdown
			*"key 1 57"*) 
				# dismiss notification screen
				display_kill
				# remove lastgame flag to prevent loading any App after next boot
				rm "${FLAGS_DIR}/lastgame.lock"
				# turn off screen
				echo 0 > /sys/devices/virtual/disp/disp/attr/lcdbl
				break
				;;
        esac
    done
fi

# notify user with vibration and led 
echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
vibrate

# kill principle and runtime first so no new app / MainUI will be loaded anymore
killall -q -15 runtime.sh
killall -q -15 principal.sh

# kill enforceSmartCPU first so no CPU setting is changed during shutdown
killall -q -15 enforceSmartCPU.sh

# kill app if not emulator is running 
if cat /tmp/cmd_to_run.sh | grep -q -v '/mnt/SDCARD/Emu' ; then
	kill_current_process
	# remove lastgame flag to prevent loading any App after next boot
	rm "${FLAGS_DIR}/lastgame.lock"
fi

# kill PICO8 if PICO8 is running
if pgrep "pico8_dyn" > /dev/null; then
	killall -q -15 pico8_dyn
fi

# trigger auto save and send kill signal 
if pgrep "ra32.miyoo" > /dev/null ; then
	# {
	#     echo 1 1 0   # MENU up
	#     echo 1 57 1  # A down
	#     echo 1 57 0  # A up
	#     echo 0 0 0   # tell sendevent to exit
	# } | $BIN_PATH/sendevent /dev/input/event3
	# sleep 0.3
	killall -q -15 ra32.miyoo
elif pgrep "PPSSPPSDL" > /dev/null ; then
	{
		echo 1 314 1  # SELECT down
		echo 3 2 255  # L2 down
		echo 3 2 0    # L2 up
		echo 1 314 0  # SELECT up
		echo 0 0 0    # tell sendevent to exit
	} | $BIN_PATH/sendevent /dev/input/event4
	sleep 1
	killall -q -15 PPSSPPSDL
else
	killall -q -15 retroarch
	killall -q -15 drastic
	killall -q -9 MainUI
fi

# wait until emulator or MainUI exit 
while killall -q -0 ra32.miyoo || \
		killall -q -0 retroarch || \
		killall -q -0 PPSSPPSDL || \
		killall -q -0 drastic || \
		killall -q -0 MainUI ; do 
	sleep 0.5
done

# show saving screen
show_image "/mnt/SDCARD/.tmp_update/res/save.png"

# Created save_active flag
flag_add "save_active"

# Saved current sound settings
alsactl store

# All processes should have been killed, safe to update time if enabled
/mnt/SDCARD/spruce/scripts/geoip_timesync.sh

# sync files and power off device
sync
poweroff
