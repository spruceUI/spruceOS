#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

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

# exit if MainUI is running
if flag_check "in_menu" ; then
	return 0
fi

# kill app without reboot if not emulator is running 
if cat /tmp/cmd_to_run.sh | grep -q -v '/mnt/SDCARD/Emu' ; then
	kill_current_process
	return 0
fi

# kill PICO8 without reboot if PICO8 is running
if pgrep "pico8_dyn" > /dev/null; then
	killall -q -15 pico8_dyn
	return 0
fi

# notify user with vibration and led 
echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
vibrate

# kill principle and runtime first so no new app / MainUI will be loaded anymore
killall -q -15 runtime.sh
killall -q -15 principal.sh

# kill enforceSmartCPU first so no CPU setting is changed during shutdown
killall -q -15 enforceSmartCPU.sh

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

# sync files and power off device
sync
poweroff