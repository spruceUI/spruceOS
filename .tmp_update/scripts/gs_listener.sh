#!/bin/sh

. /mnt/SDCARD/.tmp_update/scripts/keycodes.sh

do_this() {
	killall -15 retroarch || killall -15 /mnt/SDCARD/RetroArch/retroarch || killall -15 ra32.miyoo || killall -15 /mnt/SDCARD/RetroArch/ra32.miyoo
	touch "/mnt/SDCARD/.tmp_update/flags/gs_activated"
	sleep 1
}

exec_on_hotkey "do_this" "$B_B" "$B_DOWN" "$B_L2" "$B_R2" &
