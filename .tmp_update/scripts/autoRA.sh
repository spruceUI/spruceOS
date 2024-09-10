#!/bin/sh

check_and_connect_wifi() {
    if ! ifconfig wlan0 | grep -qE "inet |inet6 "; then
        ifconfig wlan0 up
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
        udhcpc -i wlan0 &

        for i in $(seq 1 15); do
			# Try to ping retroachievements.org to validate the connection
			if ping -c 1 -W 1 retroachievements.org >/dev/null 2>&1; then
				break
			fi
            sleep 1
        done
    fi
}

if test -f /mnt/SDCARD/.tmp_update/flags/.save_active; then
    if grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
        check_and_connect_wifi
    fi
    keymon &
    /mnt/SDCARD/.tmp_update/flags/.lastgame &> /dev/null
    /mnt/SDCARD/.tmp_update/scripts/select.sh &> /dev/null
fi
