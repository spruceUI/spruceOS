#!/bin/sh

# This script is a wrapper to take action on an idle event sourced from:
# ./idlemon -p MainUI -t 30 -c 5 -s "/mnt/SDCARD/spruce/scripts/idlemon_actionWrapper.sh" -i

[ -z "$1" ] && exit 1

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
process_name=$1

# Handle different process names....
case "$process_name" in
    MainUI)
        vibrate
        sync
        poweroff
        ;;
    /mnt/SDCARD/RetroArch/ra32.miyoo)
        #/mnt/SDCARD/spruce/scripts/SUPER-DUPER-CLEAN-SHUTDOWN-TBD.sh
        ;;
    *)
        exit 1
        ;;
esac
