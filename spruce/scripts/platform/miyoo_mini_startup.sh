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
/customer/app/keymon &

touch /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/bin/python/bin/python3.10 /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/profile /etc/profile
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/passwd /etc/passwd
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/group /etc/group


mount -o bind /mnt/SDCARD/RetroArch/ra32.mini /mnt/SDCARD/RetroArch/retroarch

(
    # On a first boot PyUI has not copied its template to Saves/ yet; read the
    # template it will copy (wifi defaults to 1) instead of skipping the whole
    # bring-up and leaving wlan0 to PyUI minutes later, after firstboot.
    system_json="/mnt/SDCARD/Saves/mini-flip-system.json"
    [ -f "$system_json" ] || system_json="/mnt/SDCARD/App/PyUI/main-ui/devices/miyoo/mini/mini-flip-system.json"
    wifi_enabled="$(jq -r '.wifi // 0' "$system_json" 2>/dev/null)"
    # Only the Mini Plus and Mini Flip have the RTL8188FU radio; the OG Mini and
    # V4 do not, and the template's wifi=1 would otherwise send them through
    # insmod / axp_test / wpa_supplicant for nothing. Same discriminator as
    # is_mini_og in device_functions/MiyooMini.sh: axp_test ships only with the
    # AXP223 (WiFi) models. adbd stays inside - on the Mini it is network ADB.
    if [ -e /customer/app/axp_test ] && [ "${wifi_enabled:-0}" = "1" ]; then
        insmod /mnt/SDCARD/spruce/miyoomini/drivers/8188fu.ko
        ifconfig lo up
        /customer/app/axp_test wifion
        sleep 2
        ifconfig wlan0 up
        wpa_supplicant -B -D nl80211 -i wlan0 -c /mnt/SDCARD/Saves/spruce/wpa_supplicant.conf
        udhcpc -i wlan0 -s /etc/init.d/udhcpc.script &
        adbd &
    fi
) &

cd /mnt/SDCARD/spruce/scripts

(
    sleep 5
    send_event /dev/input/event0 115:1
    send_event /dev/input/event0 114:1
) &

./runtime.sh
