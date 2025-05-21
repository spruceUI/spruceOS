#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh

# This is the main script that drives the BitPal menus. Each menu
# page is generated from a json array; each item in this array has
# a "value" field that stores a command to get executed when the user
# presses the A button on that item. By storing the present script
# with one or more arguments in that field, we can call a sequence of
# functions to control the menu flow and display information.

case "$1" in

    # Main menu item 1
    status | stats) 
        display_bitpal_stats
        # return to main menu after viewing stats
        call_menu "BitPal - Main" "main.json"
        ;;

    # Main menu item 2
    new)
        if missions_full; then
            display -p 50 --okay -s 36 -t "You already have 5 missions. You must complete or cancel some of these before accepting a new one."
            call_menu "BitPal - Main" "main.json"
        else
            generate_3_missions
            construct_new_mission_menu
            call_menu "BitPal - New Mission" "new_mission.json" || call_menu "BitPal - Main" "main.json"
        fi
        ;;

    # Main menu item 3
    view_active)
        if missions_empty; then
            display -p 50 --okay -s 36 -t "You don't currently have any missions! You must accept one or more missions before you can manage them."
            call_menu "BitPal - Main" "main.json"
        else
            construct_active_missions_menu
            call_menu "BitPal - Current Missions" "active_missions.json" || call_menu "BitPal - Main" "main.json"
        fi
        ;;

    # Main menu item 4
    history)
        return
        ;;

    # New Mission menu items 1-3; $2 should be 1, 2, or 3.
    accept)
        selected_mission="/tmp/new_mission${2}"
        accept_mission "$selected_mission"
        display -p 50 -d 2 -s 36 -t "Mission accepted!"
        display_mission_details "$2"
        construct_active_missions_menu
        call_menu "BitPal - Current Missions" "active_missions.json" || call_menu "BitPal - Main" "main.json"
        ;;

    # Active mission menu items 1-5; $2 should be 1,2,3,4,5
    manage_mission)
        construct_individual_mission_menu "$2"
        display_mission_details "$2"
        call_menu "BitPal - Mission $2" "manage_mission.json" || call_menu "BitPal - Current Missions" "active_missions.json"
        ;;

    # Manage (individual) mission menu item 1; $2 should
    # be 1,2,3,4,5 passed from manage_mission above
    view_mission_details)
        display_mission_details "$2"
        construct_active_missions_menu
        call_menu "BitPal - Current Missions" "active_missions.json" || call_menu "BitPal - Main" "main.json"
        ;;

    queue_game)
        launch_mission "$2"
        ;;

    cancel_mission)
        return

        ;;
    *)
        return
        ;;
esac
