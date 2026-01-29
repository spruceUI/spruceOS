#!/bin/sh

# set stick to d-pad mode
killall -q -USR2 joystickinput

cd /mnt/SDCARD/Roms/PORTS/dinojump
./dino_jump

# set stick to analog mode
killall -q -USR1 joystickinput
