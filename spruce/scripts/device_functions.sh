#!/bin/sh

get_python_path() {
    if [ "$PLATFORM" = "A30" ]; then
        echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10"
    elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]|| [ "$PLATFORM" = "SmartProS" ] || [ "$PLATFORM" = "Flip" ]; then
        echo "/mnt/SDCARD/spruce/flip/bin/python3.10"
    fi
}

export_ld_library_path() {
    case "$PLATFORM" in
        "A30") export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/a30/lib:/usr/miyoo/lib:/usr/lib:/lib" ;;
        "Flip") export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:/usr/miyoo/lib:/usr/lib:/lib" ;;
        "Brick") export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib" ;;
        "SmartPro"*) export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib" ;;
    esac
}

get_sd_card_path() {
    if [ "$PLATFORM" = "Flip" ]; then
        echo "/mnt/sdcard"
    else
        echo "/mnt/SDCARD"
    fi
}

get_config_path() {
    local cfgname
    case "$PLATFORM" in
        "A30") cfgname="a30" ;;
        "Flip") cfgname="flip" ;;
        "Brick") cfgname="brick" ;;
        "SmartPro") cfgname="smartpro" ;;
        *) cfgname="unknown" ;;  # optional default
    esac

    # Return the full path
    echo "/mnt/SDCARD/Saves/${cfgname}-system.json"
}



