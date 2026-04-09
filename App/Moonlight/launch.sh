#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APPDIR="$(dirname "$0")"

case "$BRAND" in
    "TrimUI")
        # Use firmware-provided moonlight
        cd /usr/trimui/apps/moonlight
        export LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
        echo 1 > /tmp/stay_awake
        ./moonlightui
        rm -f /tmp/stay_awake
        ;;
    *)
        # Use bundled moonlight-embedded + LÖVE GUI
        GAMEDIR="$APPDIR/ports/moonlightnew"
        MOONDIR="$GAMEDIR/moonlight"

        cd "$GAMEDIR"

        export XDG_DATA_HOME="$GAMEDIR/conf/"
        export LD_LIBRARY_PATH="$MOONDIR/libs:$LD_LIBRARY_PATH"

        chmod +x ./love
        chmod +x ./moonlight/moonlight
        ./love gui

        cd "$MOONDIR"
        COMMAND=$(cat command.txt)

        export GAMEDIR
        eval "./moonlight $COMMAND"

        rm -f command.txt
        ;;
esac

printf "\033c" > /dev/tty0
