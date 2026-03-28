#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Keymon is what originally handles the fn buttons. We will need to use this 
# script to replace that functionality. The switch has its own watcher - trimui_scened.


# we stow all our function scripts in $SPRUCE_FN_DIR/switch and $SPRUCE_FN_DIR/button.
SPRUCE_FN_DIR="/mnt/SDCARD/spruce/platform/device_functions/utils/trimui-fn"

# Place scripts here to be called when using the function switch.
# Switch up (off) = sends a 0 as the first argument to the script.
# Switch down (on) = sends a 1 as the first argument to the script.
SWITCH_DIR=/usr/trimui/scene

# Put scripts here to be called by device_L3/R3_button_pressed() via buttons_watchdog.sh
BUTTON_DIR=/tmp/spruce_fnkey


SPRUCE_JSON=/mnt/SDCARD/Saves/spruce/spruce-config.json

get_fn1_val() {
    if [ "$PLATFORM" = "Brick" ]; then
        get_config_value '.menuOptions."Fn Key and Switch Settings".fn1.selected' "Nothing"
    else
        echo -n ""
    fi
}

get_fn2_val() {
    if [ "$PLATFORM" = "Brick" ]; then
        get_config_value '.menuOptions."Fn Key and Switch Settings".fn2.selected' "Nothing"
    else
        echo -n ""
    fi
}

get_switch_val() {
    case "$PLATFORM" in
        "Brick")     get_config_value '.menuOptions."Fn Key and Switch Settings".switchBrick.selected' "D-pad <-> Analog" ;;
        "SmartPro")  get_config_value '.menuOptions."Fn Key and Switch Settings".switchTSP.selected'   "Nothing"          ;;
        "SmartProS") get_config_value '.menuOptions."Fn Key and Switch Settings".switchTSPS.selected'  "Nothing"          ;;
    esac
}


get_script_from_menu_description() {
    case "$1" in

        "D-pad <-> Analog") echo "toggle_joystick.sh" ;;
        "Toggle LEDS")      echo "toggle_leds.sh" ;;
        "Toggle Mute")      echo "toggle_mute.sh" ;;
        "Toggle Fan")       echo "toggle_fan.sh" ;;

        "Select")           echo "send_select.sh" ;;
        "Start")            echo "send_start.sh" ;;
        "Menu")             echo "send_menu.sh" ;;

        *)                  echo "" ;;
    esac
}

init_tmp_dirs() {
    mkdir -p /tmp/trimui_inputd
    mkdir -p /tmp/system

    # clear out the scened dir so it only does what spruce tells it to.
    rm -rf "$SWITCH_DIR"
    mkdir -p "$SWITCH_DIR"

    rm -rf "$BUTTON_DIR"
    mkdir -p "$BUTTON_DIR"
}

update_scripts_to_run() {

    # Clean out remnant scripts
    rm -f "$SWITCH_DIR"/*
    rm -f "$BUTTON_DIR"/*

    switch_val="$(get_switch_val)"
    fn1_val="$(get_fn1_val)"
    fn2_val="$(get_fn2_val)"

    fn1_script="$(get_script_from_menu_description "$fn1_val")"
    fn2_script="$(get_script_from_menu_description "$fn2_val")"
    switch_script="$(get_script_from_menu_description "$switch_val")"

    if [ -n "$switch_script" ] && [ -f "$SPRUCE_FN_DIR/switch/$switch_script" ]; then
        cp -f "$SPRUCE_FN_DIR/switch/$switch_script" "$SWITCH_DIR"/
    fi
    if [ -n "$fn1_script" ] && [ -f "$SPRUCE_FN_DIR/button/$fn1_script" ]; then
        cp -f "$SPRUCE_FN_DIR/button/$fn1_script" "$BUTTON_DIR"/fn1.sh
    fi
    if [ -n "$fn2_script" ] && [ -f "$SPRUCE_FN_DIR/button/$fn2_script" ]; then
        cp -f "$SPRUCE_FN_DIR/button/$fn2_script" "$BUTTON_DIR"/fn2.sh
    fi
}

values_differ() {
    [ "$1" != "$2" ]
}


monitor_for_config_changes() {

    prev_fn1="$(get_fn1_val)"
    prev_fn2="$(get_fn2_val)"
    prev_switch="$(get_switch_val)"

    while true; do
        inotifywait -e modify -e create -e moved_to "$SPRUCE_JSON"

        sleep 0.1

        next_fn1="$(get_fn1_val)"
        next_fn2="$(get_fn2_val)"
        next_switch="$(get_switch_val)"

        if \
            values_differ "$prev_fn1" "$next_fn1" || \
            values_differ "$prev_fn2" "$next_fn2" || \
            values_differ "$prev_switch" "$next_switch"
        then
            update_scripts_to_run
            prev_fn1="$next_fn1"
            prev_fn2="$next_fn2"
            prev_switch="$next_switch"
        fi
    done
}

################
##### MAIN #####
################

init_tmp_dirs
update_scripts_to_run
monitor_for_config_changes
