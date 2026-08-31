#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APPDIR="$(dirname "$0")"

GAMEDIR="$APPDIR/ports/moonlightnew"
MOONDIR="$GAMEDIR/moonlight"

cd "$GAMEDIR"

export XDG_DATA_HOME="$GAMEDIR/conf/"
export LD_LIBRARY_PATH="$MOONDIR/libs:$LD_LIBRARY_PATH"

echo 1 > /tmp/stay_awake

chmod +x ./love
chmod +x ./moonlight/moonlight
./love gui

cd "$MOONDIR"
export GAMEDIR

# No command.txt means the GUI was closed without picking an app.
#
# It is written by gui/main.lua, one argument per line. Read it that way:
# word-splitting it would neither strip quotes nor expand anything, so an app
# name with spaces would arrive as several arguments. "stream" and -keydir go
# on here because this is the script that knows GAMEDIR.
if [ -f command.txt ]; then
    set -- stream -keydir "$GAMEDIR/keys"
    while IFS= read -r moonlight_arg || [ -n "$moonlight_arg" ]; do
        [ -n "$moonlight_arg" ] && set -- "$@" "$moonlight_arg"
    done < command.txt

    /mnt/SDCARD/spruce/bin64/gptokeyb "moonlight" &
    ./moonlight "$@"
    kill -9 $(pidof gptokeyb) 2>/dev/null
fi

rm -f command.txt
rm -f /tmp/stay_awake

printf "\033c" > /dev/tty0
