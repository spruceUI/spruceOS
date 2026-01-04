#!/bin/sh

export PATH="/mnt/SDCARD/spruce/miyoomini/bin:/mnt/SDCARD/spruce/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib/:/config/lib/:/customer/lib:/mnt/SDCARD/miyoo/lib"

audioserver &
/mnt/SDCARD/spruce/miyoomini/bin/keymon &

touch /mnt/SDCARD/spruce/miyoomini/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/bin/python/bin/python3.10 /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/profile /etc/profile
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/passwd /etc/passwd
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/group /etc/group


mount -o bind /mnt/SDCARD/spruce/miyoomini/RetroArch/retroarch /mnt/SDCARD/RetroArch/retroarch

cp /mnt/SDCARD/spruce/miyoomini/RetroArch/.retroarch/retroarch.cfg /mnt/SDCARD/RetroArch/.retroarch/retroarch.cfg

(
    insmod /mnt/SDCARD/spruce/miyoomini/drivers/8188fu.ko
    ifconfig lo up
    /customer/app/axp_test wifion
    sleep 2
    ifconfig wlan0 up
    wpa_supplicant -B -D nl80211 -i wlan0 -c /appconfigs/wpa_supplicant.conf
    adbd &
) &

cd /mnt/SDCARD/spruce/scripts

(
    sleep 5
    send_event /dev/input/event0 115:1
    send_event /dev/input/event0 114:1
) &

./runtime.sh
