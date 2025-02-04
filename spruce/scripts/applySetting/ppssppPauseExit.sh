#!/bin/sh

if [ "$1" = "1" ]; then
    echo -n "PPSSPP will return to the emulator menu on exit"
    return 0
elif [ "$1" = "0" ]; then
    echo -n "PPSSPP will quit to MainUI on exit"
    return 0
fi