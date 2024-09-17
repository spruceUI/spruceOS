#!/bin/sh
. /mnt/SDCARD/.tmp_update/scripts/globalFunctions.sh

messages_file="/var/log/messages"
last_line=$(tail -n 1 "$messages_file")

case "$last_line" in
    *"rctrl_pressed"*)
        log_message "Right control pressed, showing pressstart.png"
        show_image /mnt/SDCARD/.tmp_update/res/pressstart.png 1

        log_message "Entering input loop"
        while true; do
            last_line=$(tail -n 1 "$messages_file")

            case "$last_line" in
                *"enter_pressed 0"*)
                    log_message "Start pressed, shutting down"
                    /mnt/SDCARD/.tmp_update/scripts/apaga.sh
                    break
                    ;;
                *"key 1 29 0 , postpone dimmed state"*)
                    log_message "Key 29 pressed, removing .save_active flag"
                    rm /mnt/SDCARD/.tmp_update/.save_active
                    # log_message "Running principal.sh"
                    # /mnt/SDCARD/.tmp_update/scripts/principal.sh
                    break
                    ;;
            esac
            log_message "No matching input, vibrating and waiting"
            sleep 1
        done
        log_message "Exiting input loop"
        break
        ;;
    # *)
    #    log_message "No matching condition, running principal.sh"
    #    /mnt/SDCARD/.tmp_update/scripts/principal.sh
    #    ;;
esac

