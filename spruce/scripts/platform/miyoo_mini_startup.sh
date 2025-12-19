#!/bin/sh

export PATH="/mnt/SDCARD/spruce/miyoomini/bin:$PATH" 
export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib/:/config/lib/:/customer/lib"
    
audioserver &
/mnt/SDCARD/spruce/miyoomini/bin/keymon &
insmod /mnt/SDCARD/spruce/miyoomini/drivers/8188fu.ko
ifconfig lo up
/customer/app/axp_test wifion
sleep 2
ifconfig wlan0 up
wpa_supplicant -B -D nl80211 -i wlan0 -c /appconfigs/wpa_supplicant.conf
    
touch /mnt/SDCARD/spruce/miyoomini/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/miyoomini/bin/python /mnt/SDCARD/spruce/miyoomini/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/profile /etc/profile
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/passwd /etc/passwd
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/group /etc/group

adbd &
 
cd /mnt/SDCARD/spruce/scripts
./runtime.sh
