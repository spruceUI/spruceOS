#!/bin/sh

APP_DIR=/mnt/SDCARD/App/spruceHelp

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


ICON_IMAGE="/mnt/SDCARD/spruce/imgs/expertappswitch.png"
HOMEKEY_IMAGE="$APP_DIR/imgs/homeKey.png"
POWERKEY_IMAGE="$APP_DIR/imgs/powerKey.png"
HOTKEY_IMAGE="$APP_DIR/imgs/hotkeyDefaults.png"
IMAGE_CONTINUE_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayContinueExit.png"
IMAGE_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayExit.png"
DIRECTION_PROMPTS="/mnt/SDCARD/miyoo/res/imgs/displayLeftRight.png"
WIKI_QR_CODE="https://github.com/spruceUI/spruceOS/wiki"
SPRUCE_LOGO_BG="/mnt/SDCARD/spruce/imgs/bg_tree_sm.png"
SPRUCE_VERSION=$(get_version)

show_slide() {
    local slide_number=$1
    case $slide_number in
        1)
            display -i "$SPRUCE_LOGO_BG" -t "spruceV$SPRUCE_VERSION                                                      






 Welcome to the SpruceUI Sapling Guide" -p 20 --add-image "$IMAGE_EXIT" 1.0 240 middle --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
            ;;
        2)
            display -i "$HOTKEY_IMAGE" -t " " --add-image "$IMAGE_EXIT" 1.0 240 middle --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
            ;;
        3)
            display -t "With default settings, holding the home key will open game switcher. Tapping home will open the menu or exit the current app. You can change these settings in the Advanced Settings app." -s 27 -p 170 --add-image "$HOMEKEY_IMAGE" 1.0 210 middle --add-image "$IMAGE_EXIT" 1.0 240 middle --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
            ;;
        4)
            display -t "Spruce has an auto save and shutdown feature. Hold the power key for 2 seconds and spruce will save your game. Next time you turn it on spruce will automatically resume your game." -s 27 -p 260 --add-image "$POWERKEY_IMAGE" 1.0 210 middle --add-image "$IMAGE_EXIT" 1.0 240 middle --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
            ;;
        5)
            display --icon "$ICON_IMAGE" -t "Be sure to check the Advanced Settings app for so many options to customize your spruce experience." -p 260 --add-image "$IMAGE_EXIT" 1.0 240 middle --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
            ;;
        6)
            display -t "Scan the QR Code to check out the wiki.
Or go to: github.com/spruceUI/spruceOS/wiki
There's plenty of guides and information there!" --qr "$WIKI_QR_CODE" -s 27 --add-image "$IMAGE_EXIT" 1.0 240 middle --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

#record_start

# UPDATE THESE VALUES WHEN YOU ADD OR REMOVE SLIDES
current_slide=1
total_slides=6

# Main loop
current_slide=1
show_slide $current_slide
while true; do
    
    action=$(get_button_press)
    case $action in
        "RIGHT"|"A")
            if [ $current_slide -lt $total_slides ]; then
                current_slide=$((current_slide + 1))
                show_slide $current_slide
            else
                display_kill
                record_stop &
                exit 0
            fi
            ;;
        "LEFT")
            if [ $current_slide -gt 1 ]; then
                current_slide=$((current_slide - 1))
                show_slide $current_slide
            fi
            ;;
        "UP")
            # Insert fun scripts here
            ;;
        "DOWN")
            # Insert fun scripts here
            ;;
        "B")
            display_kill
            #record_stop &
            exit 0
            ;;
    esac
done
