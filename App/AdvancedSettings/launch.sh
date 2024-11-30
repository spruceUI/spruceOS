#!/bin/sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"

# send signal USR2 to joystickinput to switch to KEYBOARD MODE
# this allows joystick to be used as DPAD in setting app
killall -q -USR2 joystickinput

cd $BIN_PATH
./easyConfig $SETTINGS_PATH/spruce_config 

# send signal USR1 to joystickinput to switch to ANALOG MODE
killall -q -USR1 joystickinput

auto_regen_tmp_update
