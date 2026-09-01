#!/bin/bash

. /mnt/SDCARD/spruce/scripts/platform/device_functions/AnbernicXXCommon.sh

# TEMPORARY (2026-09-01): the RG28XX runs as a device WITHOUT WiFi.
#
# Its radio is a USB RTL8188EU that spruce has to drive itself, and on BaseOS
# the shipped 8188eu.ko fails to insmod (EINVAL - SPR-MED-177), so wlan0 never
# exists. With no wlan0 the XX-common recovery then runs on every boot and
# after every game: rmmod/insmod of an 8821cs that is not on this model, a
# rescan of an empty SDIO host, and an unbind/rebind of the sunxi-wlan
# platform device - the step the 2026-08-31 card captures show never
# returning ("rail cycle attempt 2" is the last line, every boot). Until the
# driver question is settled the whole WiFi path is switched off here, so the
# device's behaviour without it can be observed: no module load, no
# supplicant, no DHCP client, no network services, no update check, and PyUI
# (devices/anbernic/anbernic_rg28xx.py) hides WiFi the same way.
#
# To restore WiFi: put the insmod back in device_init and delete the four
# overrides below. helperFunctions.sh's wifi_available_on_device() is what
# every caller consults, so nothing else needs to change.
device_init() {
	anbernic_xx_common_init
}

device_has_wifi_radio() {
	return 1 # False - see the note above
}

device_wifi_is_available() {
	return 1 # False - see the note above
}

device_wifi_power_on() {
	log_message "WiFi: RG28XX runs as a no-WiFi device, power_on ignored" -v
}

device_wifi_power_off() {
	:
}

device_ensure_wifi_interface() {
	return 1
}
