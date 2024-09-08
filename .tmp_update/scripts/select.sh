#!/bin/sh

messages_file="/var/log/messages"
last_line=$(tail -n 1 "$messages_file")

case "$last_line" in
    *"rctrl_pressed"*)
        show /mnt/SDCARD/.tmp_update/res/pressstart.png &                           
        sleep 1                                                                     
        killall show       

        while true; do
            last_line=$(tail -n 1 "$messages_file")

            case "$last_line" in
                *"enter_pressed 0"*)
                    /mnt/SDCARD/.tmp_update/scripts/apaga.sh
                    break
                    ;;
                *"key 1 29 0 , postpone dimmed state"*)
                    rm /mnt/SDCARD/.tmp_update/.save_active # && /mnt/SDCARD/.tmp_update/scripts/principal.sh
                    break
                    ;;
            esac

            sleep 1
        done
        break
        ;;
    # *)
    #    /mnt/SDCARD/.tmp_update/scripts/principal.sh
    #    ;;
esac

