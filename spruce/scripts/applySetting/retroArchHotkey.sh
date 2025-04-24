#!/bin/sh

# this import is needed, for platform detection and logging
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

RETROARCH_CFG="/mnt/SDCARD/spruce/settings/platform/retroarch-$PLATFORM.cfg"
TMP_CFG="/tmp/retroarch.cfg"

# set key line + value mappings per platform
case "$PLATFORM" in
    "A30")
        HOTKEY_LINE="input_enable_hotkey"
        SELECT_VAL="rctrl"
        START_VAL="enter"
        HOME_VAL="escape"
        ;;
    *)
        HOTKEY_LINE="input_enable_hotkey_btn"
        SELECT_VAL="4"
        START_VAL="6"
        HOME_VAL="5"
        ;;
esac

# universal Off value to assign
OFF_VAL="nul"

if [ "$1" = "check" ]; then
    hotkey_value=$(grep "^$HOTKEY_LINE = " "$RETROARCH_CFG" | cut -d '"' -f 2 | tr -d '\r\n')

    case "$hotkey_value" in
    "nul" | "z" | "")
        echo -n "Off"
        ;;
    "$SELECT_VAL")
        echo -n "Select"
        ;;
    "$START_VAL")
        echo -n "Start"
        ;;
    "$HOME_VAL")
        echo -n "Home"
        ;;
    *)
        echo -n "Custom"
        ;;
    esac
fi

if [ "$1" = "check_simple" ]; then
    hotkey_value=$(grep "^$HOTKEY_LINE = " "$RETROARCH_CFG" | cut -d '"' -f 2 | tr -d '\r\n')

    case "$hotkey_value" in
    "nul" | "z" | "")
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
        log_message "RetroArch hotkey set to Select"
        log_message "Running: sed 's/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$SELECT_VAL\"/' \"$RETROARCH_CFG\"" -v
        sed "s/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$SELECT_VAL\"/" "$RETROARCH_CFG" > "$TMP_CFG"
        cp -f "$TMP_CFG" "$RETROARCH_CFG"
        ;;
    "Start")
        log_message "RetroArch hotkey set to Start"
        log_message "Running: sed 's/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$START_VAL\"/' \"$RETROARCH_CFG\"" -v
        sed "s/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$START_VAL\"/" "$RETROARCH_CFG" > "$TMP_CFG"
        cp -f "$TMP_CFG" "$RETROARCH_CFG"
        ;;
    "Home")
        log_message "RetroArch hotkey set to Home"
        log_message "Running: sed 's/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$HOME_VAL\"/' \"$RETROARCH_CFG\"" -v
        sed "s/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$HOME_VAL\"/" "$RETROARCH_CFG" > "$TMP_CFG"
        cp -f "$TMP_CFG" "$RETROARCH_CFG"
        ;;
    "Off" | "on")
        log_message "RetroArch hotkey disabled"
        log_message "Running: sed 's/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$OFF_VAL\"/' \"$RETROARCH_CFG\"" -v
        sed "s/^$HOTKEY_LINE = .*/$HOTKEY_LINE = \"$OFF_VAL\"/" "$RETROARCH_CFG" > "$TMP_CFG"
        cp -f "$TMP_CFG" "$RETROARCH_CFG"
        ;;
    *)
        log_message "Invalid hotkey assignment: $2"
        ;;
    esac
fi
