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
        if missions_full; then
            display -p 50 --okay -s 36 -t "You already have 5 missions. You must complete or cancel some of these before accepting a new one."
            call_menu "BitPal - Main" "main.json"
        else
            generate_3_missions
            construct_new_mission_menu
            call_menu "BitPal - New Mission" "new_mission.json"
        fi
        ;;
    accept)
        selected_mission="/tmp/new_mission${2}"
        accept_mission "$selected_mission"
        display -p 50 -d 2 -s 36 -t "Mission accepted!"
        call_menu "BitPal - Main" "main.json"
        ;;
    view_active)
        if missions_empty; then
            display -p 50 --okay -s 36 -t "You don't currently have any missions! You must accept one or more missions before you can manage them."
            call_menu "BitPal - Main" "main.json"
        else
            construct_active_missions_menu
            call_menu "BitPal - Active Missions" "active_missions.json"
        fi
        ;;
    view_mission_details)
        display_mission_details "$2"
        call_menu "BitPal - Current Missions" "active_missions.json"
        ;;
    manage_mission)
        construct_individual_mission_menu "$2"
        display_mission_details "$2"
        call_menu "BitPal - Mission $2" "manage_mission.json"
        ;;
    queue_game)
        launch_mission "$2"
        ;;
    cancel_mission)
        return

        ;;
    history)
        return
        ;;
    *)
        return
        ;;
esac
