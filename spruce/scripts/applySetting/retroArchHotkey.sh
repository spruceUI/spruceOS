#input_enable_hotkey = "rctrl"

RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"
# Check flag and print on/off (without newline) as return value
# This is placed before loading helping functions for fast checking
if [ "$1" = "check" ]; then
    if grep -q '^input_enable_hotkey = "nul"' "$RETROARCH_CFG" || grep -q '^input_enable_hotkey = "z"' "$RETROARCH_CFG"; then
        echo -n "off"
    else
        echo -n "on"
    fi
    return 0
fi


. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


if [ "$1" = "on" ]; then
    log_message "RetroArch hotkey enabled"
    sed -i 's/^input_enable_hotkey = .*/input_enable_hotkey = "rctrl"/' "$RETROARCH_CFG"
elif [ "$1" = "off" ]; then
    log_message "RetroArch hotkey disabled"
    sed -i 's/^input_enable_hotkey = .*/input_enable_hotkey = "z"/' "$RETROARCH_CFG"
fi
