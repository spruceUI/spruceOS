#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"
messages_file="/var/log/messages"

set_performance
log_message "AutoRA: Save active flag detected"

#Set the LED
if flag_check "ledon"; then
	echo 1 > "$LED_PATH"/brightness
else
	echo 0 > "$LED_PATH"/brightness
fi

# move command to cmd_to_run.sh so game switcher can work correctly
mv "${FLAGS_DIR}/lastgame.lock" /tmp/cmd_to_run.sh && sync

# load a dummy SDL program and try to initialize GPU and other hardware before loading game
./easyConfig &> /dev/null &

log_message "AutoRA: load game to play"
sleep 5
nice -n -20 /tmp/cmd_to_run.sh &> /dev/null

# remove tmp command file after game exit
# otherwise the game will load again in principle.sh later
rm -f /tmp/cmd_to_run.sh
