#!/bin/sh
echo 30 > /sys/devices/virtual/timed_output/vibrator/enable
killall keymon &&
#killall keymon
brillo=$(cat /sys/devices/virtual/disp/disp/attr/lcdbl)
echo 0 > /sys/devices/virtual/disp/disp/attr/lcdbl
pid=$(ps|pgrep retroarch)
if [ "$pid" -gt 1 ] ; then
killall runtime.sh
killall autoRA.sh
killall principal.sh
killall -15 retroarch
sleep 1
touch  /mnt/SDCARD/.tmp_update/flags/.save_active
sleep 1
#show "/mnt/SDCARD/.tmp_update/res/save.png" &
echo $brillo > /sys/devices/virtual/disp/disp/attr/lcdbl
/mnt/SDCARD/.tmp_update/scripts/apaga.sh
else
poweroff
echo no retroarch
fi 
