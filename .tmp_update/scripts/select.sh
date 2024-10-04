#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

messages_file="/var/log/messages"
last_line=$(tail -n 1 "$messages_file")

case "$last_line" in
    *"rctrl_pressed"*)
        log_message "Select pressed, running apaga.sh"
        /mnt/SDCARD/.tmp_update/scripts/apaga.sh
        ;;
    # *)
    #    log_message "No matching condition, running principal.sh"
    #    /mnt/SDCARD/.tmp_update/scripts/principal.sh
    #    ;;
esac