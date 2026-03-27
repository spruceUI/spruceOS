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
    rm -rf $SWITCH_DIR
    mkdir -p $SWITCH_DIR
}

update_scripts_to_run() {

    case "$PLATFORM" in
        "Brick")
            switch_val=$(get_config_value '.menuOptions."Fn Key and Switch Settings".switchBrick.selected' "D-pad <-> Analog")
            fn1_val=$(get_config_value '.menuOptions."Fn Key and Switch Settings".fn1.selected' "Nothing")
            fn2_val=$(get_config_value '.menuOptions."Fn Key and Switch Settings".fn2.selected' "Nothing")
            export fn1_script="$(get_script_from_menu_description "$fn1_val")"
            export fn2_script="$(get_script_from_menu_description "$fn2_val")"
            ;;
        "SmartPro")
            switch_val=$(get_config_value '.menuOptions."Fn Key and Switch Settings".switchTSP.selected' "D-pad <-> Analog")
            ;;
        "SmartProS")
            switch_val=$(get_config_value '.menuOptions."Fn Key and Switch Settings".switchTSPS.selected' "D-pad <-> Analog")
            ;;
    esac

    export switch_script="$(get_script_from_menu_description "$switch_val")"

    if [ -f "$SPRUCE_FN_DIR/switch/$switch_script" ]; then
        cp -f "$SPRUCE_FN_DIR/switch/$switch_script" "$SWITCH_DIR"/
    fi

    # No need to copy the fn1 and fn2 scripts to NAND because we will just run them in place.
    # Only reason we copy the switch script there is because we are still using stock trimui_scened.
}



##### MAIN #####

init_tmp_dirs
update_scripts_to_run

