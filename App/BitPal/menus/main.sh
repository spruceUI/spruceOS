#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh


case "$1" in
    status | stats) 
        display_bitpal_stats
        # return to main menu after viewing stats
        call_menu "BitPal - Main" "main.json"
        ;;
    new)
        generate_3_missions
        construct_new_mission_menu
        call_menu "BitPal - New Mission" "new_mission.json" ;;
    accept)
        selected_mission="/tmp/new_mission$2"
        accept_mission "$selected_mission"
        display -p 50 -d 2 -s 36 -t "Mission accepted!"

        ;;
    *) return ;;
esac
