#!/bin/sh


####################################################
## Note: This startup is different from the rest
## of the platforms, as MiyooMini does not support
## ADB over USB. Thus to make debugging easier we
## ensure we can at least get to ADB in case anything
## else goes wrong that would crash the startup
## sequence
####################################################

export PATH="/mnt/SDCARD/spruce/miyoomini/bin:/mnt/SDCARD/spruce/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib/:/config/lib/:/customer/lib:/mnt/SDCARD/miyoo/lib"

audioserver &
/mnt/SDCARD/spruce/miyoomini/bin/keymon &

touch /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/bin/python/bin/python3.10 /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/profile /etc/profile
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/passwd /etc/passwd
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/group /etc/group


mount -o bind /mnt/SDCARD/RetroArch/retroarch.MiyooMini /mnt/SDCARD/RetroArch/retroarch

(
    insmod /mnt/SDCARD/spruce/miyoomini/drivers/8188fu.ko
    ifconfig lo up
    /customer/app/axp_test wifion
    sleep 2
    ifconfig wlan0 up
    wpa_supplicant -B -D nl80211 -i wlan0 -c /mnt/SDCARD/Saves/spruce/wpa_supplicant.conf
    udhcpc -i wlan0 -s /etc/init.d/udhcpc.script &
    adbd &
) &

cd /mnt/SDCARD/spruce/scripts

(
    sleep 5
    send_event /dev/input/event0 115:1
    send_event /dev/input/event0 114:1
) &

./runtime.sh
