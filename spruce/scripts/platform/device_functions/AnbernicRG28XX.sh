#!/bin/bash

. /mnt/SDCARD/spruce/scripts/platform/device_functions/AnbernicXXCommon.sh

# The RG28XX's radio is a USB RTL8188EU; AnbernicRG28XX.cfg selects the USB
# radio contract in AnbernicXXCommon.sh (bus-first, bounded, no sunxi-wlan and
# no sdc1 - the SDIO levers whose unbind wedged this model on every captured
# boot, SPR-MED-177). The module is loaded by device_wifi_power_on on the
# enable_wifi path, not here: nothing radio-related sits on the boot-critical
# path.
device_init() {
	anbernic_xx_common_init
}

# Radio availability on this model is two facts. A module that refused to
# load (WIFI_UNAVAILABLE_FLAG) is sticky for the session. An adapter that was
# not on the bus (WIFI_RADIO_ABSENT_FLAG) is not: the marker is re-checked
# against the bus right here, so plugging the dongle in after boot and turning
# WiFi on simply works. Both answer through spruce.log with the reason.
device_has_wifi_radio() {
	[ -e "$WIFI_UNAVAILABLE_FLAG" ] && return 1
	if [ -e "$WIFI_RADIO_ABSENT_FLAG" ]; then
		wifi_usb_radio_present || return 1
		rm -f "$WIFI_RADIO_ABSENT_FLAG" 2>/dev/null
	fi
	return 0
}

device_wifi_is_available() {
	device_has_wifi_radio
}
