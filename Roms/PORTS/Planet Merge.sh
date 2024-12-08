#!/bin/sh

# set stick to d-pad mode
killall -q -USR2 joystickinput

cd /mnt/SDCARD/Roms/PORTS/planetmerge
XDG_CONFIG_HOME=/mnt/SDCARD/Saves/ ./planets

# set stick to analog mode
killall -q -USR1 joystickinput
