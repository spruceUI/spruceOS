#!/bin/sh
# changeCmd for LED settings: apply on change instead of waiting for the
# next return to the menu. Backgrounded - PyUI runs changeCmd on the UI thread.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

(
    enable_or_disable_rgb

    # Only run on devices with RGB LEDs
    case "$PLATFORM" in
        "Brick"|"BrickOakMOSS"|"BrickPro"|"SmartPro"|"SmartProS"|"Miniloong"|"AnbernicRG"*|"AnbernicXX"*)
            set_rgb_in_menu
            ;;
        *)
            exit 0
            ;;
    esac
) </dev/null >/dev/null 2>&1 &
