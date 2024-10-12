#!/bin/sh
source /mnt/SDCARD/.tmp_update/fundidos.sh
echo 30 > /sys/devices/virtual/timed_output/vibrator/enable
cat /sys/devices/virtual/disp/disp/attr/lcdbl > /mnt/SDCARD/.tmp_update/brillo
cat /sys/devices/virtual/disp/disp/attr/enhance > /mnt/SDCARD/.tmp_update/color
fade_in
killall keymon #It is necessary to kill him because if not, he will repeat the execution until the button is released.
pid=$(ps|pgrep retroarch)
if [ "$pid" -gt 1 ] ; then
killall runtime.sh
killall autoRA2.sh
killall -15 emulationstation
killall -15 retroarch
sleep 1
touch  /mnt/SDCARD/.tmp_update/flags/.save_active
sleep 1
cat /mnt/SDCARD/.tmp_update/color > /sys/devices/virtual/disp/disp/attr/enhance
/mnt/SDCARD/.tmp_update/scripts/apaga.sh
else
killall -15 emulationstation
sleep 2
cat /mnt/SDCARD/.tmp_update/color > /sys/devices/virtual/disp/disp/attr/enhance
echo no retroarch
fi
