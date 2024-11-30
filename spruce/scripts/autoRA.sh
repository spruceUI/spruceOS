#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"
messages_file="/var/log/messages"

set_performance
log_message "AutoRA: Save active flag detected"

#Set the LED
if flag_check "ledon"; then
	echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
else
	echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
fi

# copy command to cmd_to_run.sh so game switcher can work correctly
cp "${FLAGS_DIR}/lastgame.lock" /tmp/cmd_to_run.sh

# load a dummy SDL program and try to initialize GPU and other hardware before loading game
./easyConfig &> /dev/null &

flag_remove "save_active"
log_message "AutoRA: load game to play"
sleep 5
nice -n -20 $FLAGS_DIR/lastgame.lock &> /dev/null

# remove tmp command file after game exit
# otherwise the game will load again in principle.sh later
rm -f /tmp/cmd_to_run.sh
