
#!/bin/sh
tiempo=300
killall -19 ra32.miyoo
killall -19 dino_jump
killall -19 MainUI
killall -19 drastic
dd if=/dev/zero of=/dev/fb0
display /mnt/SDCARD/.tmp_update/res/suspend.png &
echo 9 > /sys/devices/virtual/disp/disp/attr/lcdbl
sleep 3
echo +$tiempo  > /sys/class/rtc/rtc0/wakealarm
echo "mem" > /sys/power/state
