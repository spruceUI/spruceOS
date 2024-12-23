#!/bin/sh
export HOME="$(dirname "$0")"
cd "$HOME"

case "$PLATFORM" in
    "Brick" | "SmartPro" | "Flip" )
        export LD_LIBRARY_PATH="$HOME/lib64:$LD_LIBRARY_PATH"
        ;;
    "A30" )
        export LD_LIBRARY_PATH="$HOME/lib:$LD_LIBRARY_PATH"
        ;;
esac

if [ "$PLATFORM" = "A30" ]; then

	killall -q -USR2 joystickinput   # set stick to d-pad mode
	./DinguxCommander #--res-dir ${THEME_PATH} || ./DinguxCommander --res-dir /mnt/SDCARD/Themes/SPRUCE
	sync
	killall -q -USR2 joystickinput   # set stick to d-pad mode

elif [ "$PLATFORM" = "Brick" ]; then

	./DinguxCommanderBrick
	
fi


auto_regen_tmp_update