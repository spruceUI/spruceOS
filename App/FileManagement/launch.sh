#!/bin/sh
export HOME="$(dirname "$0")"
cd "$HOME"

case "$PLATFORM" in
    "Brick" | "SmartPro" )
        export LD_LIBRARY_PATH="$HOME/lib-Brick:$LD_LIBRARY_PATH"
        ;;
    "A30" )
        export LD_LIBRARY_PATH="$HOME/lib:$LD_LIBRARY_PATH"
        ;;
    "Flip" )
        export LD_LIBRARY_PATH="$HOME/lib-Flip:$LD_LIBRARY_PATH"
        ;;
esac

if [ "$PLATFORM" = "A30" ]; then

	killall -q -USR2 joystickinput   # set stick to d-pad mode
	./DinguxCommander #--res-dir ${THEME_PATH} || ./DinguxCommander --res-dir /mnt/SDCARD/Themes/SPRUCE
	sync
	killall -q -USR2 joystickinput   # set stick to d-pad mode

elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]|| [ "$PLATFORM" = "Flip" ]; then
    ./gptokeyb -k "DinguxCommander" -c "./DinguxCommander.gptk" &
    sleep 1
	  ./"DinguxCommander$PLATFORM"
    kill -9 "$(pidof gptokeyb)" 
fi


auto_regen_tmp_update
