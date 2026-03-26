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
    log_message "Starting new loop of principal.sh"
    set_smart

    stop_pyui_message_writer
    enable_or_disable_rgb
    set_rgb_in_menu
    set_network_proxy

    if [ ! -f /tmp/cmd_to_run.sh ]; then
        display_kill &          # This is to kill leftover display processes that may be running
        flag_remove "lastgame"  # create in menu flag and remove last played game flag
        flag_add "in_menu" --tmp
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

        flag_remove "in_menu"
    fi

    # clear the FB to get rid of residual Loading or Iconfresh screen if present
    touch /tmp/fbdisplay_exit
    cat /dev/zero > /dev/fb0 2>/dev/null

    # When you select a game or app, MainUI writes that command to a temp file and closes itself.
    # This section handles what becomes of that temp file.
    if [ -f /tmp/cmd_to_run.sh ]; then
        is_autoresume_launch=0
        if flag_check "autoresume_staged"; then
            is_autoresume_launch=1
            if flag_check "autoresume_consumed"; then
                log_message "Auto Resume contract violation prevented: staged command already consumed once in this boot; removing duplicate /tmp/cmd_to_run.sh"
                rm -f /tmp/cmd_to_run.sh
                flag_remove "autoresume_staged"
                continue
            fi
            flag_add "autoresume_consumed" --tmp
        fi

        if [ ! -s /tmp/cmd_to_run.sh ]; then
            log_message "cmd_to_run rejected: empty or invalid file; removing and continuing to menu."
            rm -f /tmp/cmd_to_run.sh
            [ "$is_autoresume_launch" -eq 1 ] && flag_remove "autoresume_staged"
            continue
        fi

        if ! sh -n /tmp/cmd_to_run.sh >/dev/null 2>&1; then
            log_message "cmd_to_run rejected: syntax check failed; removing and continuing to menu."
            rm -f /tmp/cmd_to_run.sh
            [ "$is_autoresume_launch" -eq 1 ] && flag_remove "autoresume_staged"
            continue
        fi

        if [ "$is_autoresume_launch" -eq 1 ]; then
            log_message "Auto Resume consume start: staged file accepted by canonical launcher"
        fi

        sync
        cmd="$(sed 's/[[:space:]]*$//' /tmp/cmd_to_run.sh)"
        log_activity_event "$cmd" "START"
        set_performance # lead with this to speed up launching

        udpbcast -f /tmp/host_msg 2>/dev/null &
        touch /tmp/miyoo_inputd/enable_turbo_input 2>/dev/null # Enables turbo buttons in-game for Flip
        chmod a+x /tmp/cmd_to_run.sh
        cp /tmp/cmd_to_run.sh "$FLAGS_DIR/lastgame.lock" # set up autoresume
        log_message "Running: $(cat /tmp/cmd_to_run.sh)"
        /tmp/cmd_to_run.sh >/dev/null 2>&1
        cmd_exit_code=$?

        rm /tmp/cmd_to_run.sh
        if [ -f /tmp/cmd_to_run.sh ]; then
            rm -f /tmp/cmd_to_run.sh
            log_message "cmd_to_run cleanup required second removal attempt"
        fi
        rm /tmp/host_msg 2>/dev/null
        rm /tmp/miyoo_inputd/enable_turbo_input 2>/dev/null # Disables turbo buttons in menu for Flip
        killall -9 udpbcast 2>/dev/null

        if [ "$is_autoresume_launch" -eq 1 ]; then
            flag_remove "autoresume_staged"
            log_message "Auto Resume consume complete: launched once via principal, exit_code=$cmd_exit_code, staged artifact removed"
        fi

        log_activity_event "$cmd" "STOP"
        sync
    fi

    if flag_check "tmp_update_repair_attempted"; then
        flag_remove "tmp_update_repair_attempted"
        log_message ".tmp_update folder repair appears to have been successful. Removing tmp_update_repair_attempted flag."
    fi

    # Bring up network services and idlemon in case they were disabled in-game or otherwise toggled
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 1 ]; then
        /mnt/SDCARD/spruce/scripts/networkservices.sh &
    fi

done
