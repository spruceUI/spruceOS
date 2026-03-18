#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Disable idle/shutdown timer while file manager is open
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

export HOME="$(dirname "$0")"
cd "$HOME"

case "$PLATFORM" in
    "SmartPro"* ) export LD_LIBRARY_PATH="$HOME/lib-Brick:$LD_LIBRARY_PATH" ;;
    * )           export LD_LIBRARY_PATH="$HOME/lib-${PLATFORM}:$LD_LIBRARY_PATH" ;;
esac

case "$PLATFORM" in
    "A30")
        killall -q -USR2 joystickinput   # set stick to d-pad mode
        ./DinguxCommanderA30
        sync
        killall -q -USR2 joystickinput   # set stick to d-pad mode
        ;;
    "SmartProS")
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./DinguxCommander.gptk" &
        sleep 0.3
        ./"DinguxCommanderSmartPro"
        sync
        kill -9 "$(pidof gptokeyb)"
        ;;
    "Pixel2")
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./DinguxCommanderPixel2.gptk" &
        sleep 0.3
        ./"DinguxCommanderFlip"
        sync
        kill -9 "$(pidof gptokeyb)"
        ;;
    "Anbernic"*)
        cd "/mnt/vendor/bin/fileM"
        /mnt/vendor/bin/fileM/dinguxCommand_en.dge
        ;;
    *)
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./DinguxCommander.gptk" &
        sleep 0.3
        ./"DinguxCommander$PLATFORM"
        sync
        kill -9 "$(pidof gptokeyb)" 
        ;;
esac
