#!/bin/sh

RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"

# bring this back if we need to add logging, but make sure it doesn't print anything on import
# . /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$1" = "check" ]; then
    hotkey_value=$(grep '^input_enable_hotkey = ' "$RETROARCH_CFG" | cut -d '"' -f 2)

    case "$hotkey_value" in
    "nul" | "z")
        echo -n "Off"
        ;;
    "rctrl")
        echo -n "Select"
        ;;
    "enter")
        echo -n "Start"
        ;;
    "escape")
        echo -n "Home"
        ;;
    *)
        echo -n "Custom"
        ;;
    esac
fi

if [ "$1" = "check_simple" ]; then
    hotkey_value=$(grep '^input_enable_hotkey = ' "$RETROARCH_CFG" | cut -d '"' -f 2)

    case "$hotkey_value" in
    "nul" | "z")
        echo -n "on"
        ;;
    *)
        echo -n "off"
        ;;
    esac
fi

if [ "$1" = "init" ]; then
    case "$2" in
    "Custom")
        echo -n "Define your own hotkey in RetroArch"
        ;;
    "Start")
        echo -n "Be aware Start+L1/R1 are hardware level brightness hotkeys"
        ;;
    "Home")
        echo -n "Be aware Home+D-Pad presses will still fire tap/hold actions"
        ;;
    *)
        echo -n "Combine with other keys for quick actions in RetroArch"
        ;;
    esac
fi

if [ "$1" = "assign" ]; then
    case "$2" in
    "Select" | "off")
        # no log calls without importing helperFunctions.sh
        # log_message "RetroArch hotkey set to Select"
        sed -i 's/^input_enable_hotkey = .*/input_enable_hotkey = "rctrl"/' "$RETROARCH_CFG"
        ;;
    "Start")
        # log_message "RetroArch hotkey set to Start"
        sed -i 's/^input_enable_hotkey = .*/input_enable_hotkey = "enter"/' "$RETROARCH_CFG"
        ;;
    "Home")
        # log_message "RetroArch hotkey set to Home"
        sed -i 's/^input_enable_hotkey = .*/input_enable_hotkey = "escape"/' "$RETROARCH_CFG"
        ;;
    "Off" | "on")
        # log_message "RetroArch hotkey disabled"
        sed -i 's/^input_enable_hotkey = .*/input_enable_hotkey = "z"/' "$RETROARCH_CFG"
        ;;
    *)
        # log_message "Invalid hotkey assignment: $2"
        ;;
    esac
fi
