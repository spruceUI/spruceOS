#!/bin/sh

APP_DIR=/mnt/SDCARD/App/spruceHelp

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


ICON_IMAGE="/mnt/SDCARD/Themes/SPRUCE/Icons/App/led.png"
HOMEKEY_IMAGE="$APP_DIR/imgs/homeKey.png"
POWERKEY_IMAGE="$APP_DIR/imgs/powerKey.png"
HOTKEY_IMAGE="$APP_DIR/imgs/hotkeyDefaults.png"
IMAGE_CONTINUE_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayContinueExit.png"
WIKI_QR_CODE=$(qr_code -t "https://github.com/spruceUI/spruceOS/wiki")
SPRUCE_LOGO_BG="/mnt/SDCARD/spruce/imgs/bg_tree_sm.png"
SPRUCE_VERSION=$(get_version)

continue_or_exit() {
    if ! confirm; then
        display_kill
        #record_stop &
        exit 0
    fi
}

#record_start

display -i "$SPRUCE_LOGO_BG" -t "Welcome to the SpruceUI Sapling Guide

spruceV$SPRUCE_VERSION                                                      " -p 345 --add-image "$IMAGE_CONTINUE_EXIT" 1.0 240 middle
continue_or_exit

display -i "$HOTKEY_IMAGE" -t " " --add-image "$IMAGE_CONTINUE_EXIT" 1.0 240 middle
continue_or_exit

display -t "With default settings, holding the home key will open game switcher. Tapping home will open the menu or exit the current app. You can change these settings in the Advanced Settings app." -s 27 -p 240 --add-image "$HOMEKEY_IMAGE" 1.0 210 middle --add-image "$IMAGE_CONTINUE_EXIT" 1.0 240 middle
continue_or_exit

display -t "Spruce has an auto save and shutdown feature. Hold the power key for 2 seconds and spruce will save your game. Next time you turn it on spruce will automatically resume your game." -s 27 -p 260 --add-image "$POWERKEY_IMAGE" 1.0 210 middle --add-image "$IMAGE_CONTINUE_EXIT" 1.0 240 middle
continue_or_exit

display --icon "$ICON_IMAGE" -t "Be sure to check the Advanced Settings app for so many options to customize your spruce experience." -p 260 --add-image "$IMAGE_CONTINUE_EXIT" 1.0 240 middle
continue_or_exit

display -t "Scan the QR Code to check out the Spruce wiki
Or go to: github.com/spruceUI/spruceOS/wiki
There's plenty of guides and information there!" --qr "$WIKI_QR_CODE" -s 27 --add-image "$IMAGE_CONTINUE_EXIT" 1.0 240 middle
continue_or_exit

#record_stop &

continue_or_exit
