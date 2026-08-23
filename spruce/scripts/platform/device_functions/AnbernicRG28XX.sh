#!/bin/bash

. /mnt/SDCARD/spruce/scripts/platform/device_functions/AnbernicXXCommon.sh

device_init() {
	# The RG28XX is the one model in the line that needs a WiFi module loaded
	# by hand - RTL8188, shipped with spruce. Everything else it needs at init
	# is shared with the rest of the XX line, so take it from there rather than
	# keeping a second copy that drifts.
	insmod /mnt/SDCARD/spruce/h700/rg28xx/8188eu.ko > /mnt/SDCARD/Saves/spruce/rg28xx_8188eu_log.txt 2>&1

	anbernic_xx_common_init
}
