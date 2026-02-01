#!/bin/sh

# This script is a wrapper to take action on an idle event sourced from:
# ./idlemon -p MainUI -t 30 -c 5 -s "/mnt/SDCARD/spruce/scripts/idlemon_actionWrapper.sh" -i

[ -z "$1" ] && exit 1

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
process_name=$1

# Handle different process names....
case "$process_name" in
    MainUI)
	    [ "$LED_PATH" != "not applicable" ] && echo heartbeat > "$LED_PATH"/trigger
		killall -q -0 MainUI
        alsactl store
		vibrate &
        sync
        poweroff
        ;;
    ra32.miyoo|ra64.miyoo|ra64.trimui|retroarch*|drastic*|PPSSPP*)
        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
        ;;
    *)
        exit 1
        ;;
esac
