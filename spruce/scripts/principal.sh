#!/bin/sh

# Principal Script for Miyoo A30
#
# This script serves as the main control loop for the system. It operates as follows:
#
# Initializes by ensuring keymon is running
# Enters an infinite loop that:
#    a. Checks for and handles game switching if necessary
#    b. If not switching games, it runs the main UI
#    c. After UI closes, it either:
#       - Loads and runs a game
#       - Or executes a custom command
# Then the loop repeats, returning to the main UI
#
# Throughout this process, it monitors various system flags and
# responds accordingly, managing the overall system state.

# Source the helper functions
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

while [ 1 ]; do

    stop_pyui_message_writer
    enable_or_disable_rgb
    set_rgb_in_menu
    set_network_proxy

    if [ ! -f /tmp/cmd_to_run.sh ]; then
        
        display_kill &          # This is to kill leftover display processes that may be running
        flag_remove "lastgame"  # create in menu flag and remove last played game flag
        flag_add "in_menu"
        low_battery_check       # Check for the low_battery flag and warn user if so

        # This is to mostly to allow themes to unpack before hitting the menu so they are immediately visible to PyUI
        finish_unpacking "pre_menu_unpacking"

        prepare_for_pyui_launch

        log_activity_event "PyUI" "START"
        /mnt/SDCARD/App/PyUI/launch.sh
        log_activity_event "PyUI" "STOP"

        post_pyui_exit

        # This is to block any games from launching before all necessary assets such as cores have been unpacked
        finish_unpacking "pre_cmd_unpacking"

        spruce/scripts/applySetting/idlemon_mm.sh reapply &

        flag_remove "in_menu"
    fi

    # clear the FB to get rid of residual Loading or Iconfresh screen if present
    touch /tmp/fbdisplay_exit
    cat /dev/zero > /dev/fb0 2>/dev/null

    # When you select a game or app, MainUI writes that command to a temp file and closes itself.
    # This section handles what becomes of that temp file.
    if [ -f /tmp/cmd_to_run.sh ]; then

        cmd="$(sed 's/[[:space:]]*$//' /tmp/cmd_to_run.sh)"
        log_activity_event "$cmd" "START"
        set_performance # lead with this to speed up launching

        udpbcast -f /tmp/host_msg 2>/dev/null &
        touch /tmp/miyoo_inputd/enable_turbo_input 2>/dev/null # Enables turbo buttons in-game for Flip
        chmod a+x /tmp/cmd_to_run.sh
        cp /tmp/cmd_to_run.sh "$FLAGS_DIR/lastgame.lock" # set up autoresume

        /tmp/cmd_to_run.sh &>/dev/null
        
        rm /tmp/cmd_to_run.sh
        rm /tmp/host_msg 2>/dev/null
        rm /tmp/miyoo_inputd/enable_turbo_input 2>/dev/null # Disables turbo buttons in menu for Flip
        killall -9 udpbcast 2>/dev/null

        set_smart
        log_activity_event "$cmd" "STOP"
    fi

    if flag_check "tmp_update_repair_attempted"; then
        flag_remove "tmp_update_repair_attempted"
        log_message ".tmp_update folder repair appears to have been successful. Removing tmp_update_repair_attempted flag."
    fi

    # Bring up network and services in case they were disabled in-game or otherwise toggled
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 1 ]; then
        /mnt/SDCARD/spruce/scripts/networkservices.sh &
    fi

done
