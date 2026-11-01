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

# A boot that the charger started shows a charge screen here and powers off, or returns to continue the boot.
# Before keymon, which would act on the POWER presses the charge screen reads.
sh /mnt/SDCARD/spruce/scripts/platform/miyoomini/charge_gate.sh

# audioserver starts in device_init, once the stock startup sound has let go of the audio device.
/customer/app/keymon &

touch /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/bin/python/bin/python3.10 /mnt/SDCARD/spruce/bin/python/bin/MainUI
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/profile /etc/profile
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/passwd /etc/passwd
mount -o bind /mnt/SDCARD/spruce/miyoomini/etc/group /etc/group


mount -o bind /mnt/SDCARD/RetroArch/ra32.mini /mnt/SDCARD/RetroArch/retroarch

(
    # On a first boot PyUI has not copied its template to Saves/ yet; read the
    # template it will copy instead of skipping the whole
    # bring-up and leaving wlan0 to PyUI minutes later, after firstboot.
    system_json="/mnt/SDCARD/Saves/miyoo-mini-system.json"
    [ -f "$system_json" ] || system_json="/mnt/SDCARD/App/PyUI/main-ui/devices/miyoo/mini/miyoo-mini-system.json"
    wifi_enabled="$(jq -r '.wifi // 0' "$system_json" 2>/dev/null)"
    # Only the Mini Plus and Mini Flip have the RTL8188FU radio; the OG Mini and
    # V4 do not, and the template's wifi=1 would otherwise send them through
    # insmod / axp_test / wpa_supplicant for nothing. Same discriminator as
    # is_mini_og in platform/MiyooMini.sh: axp_test ships only with the
    # AXP223 (WiFi) models.
    if [ -e /customer/app/axp_test ] && [ "${wifi_enabled:-0}" = "1" ]; then
        sh /mnt/SDCARD/spruce/scripts/network/wifi.sh apply --wait
    fi
) &

cd /mnt/SDCARD/spruce/scripts

(
    sleep 5
    send_event /dev/input/event0 115:1
    send_event /dev/input/event0 114:1
) &

./runtime.sh
