#!/bin/sh

if [ "$1" = "0" ]; then
    echo -n "PPSSPP will return to the emulator menu when exiting from the pause menu"
    return 0
elif [ "$1" = "1" ]; then
    echo -n "PPSSPP will quit to MainUI when exiting from the pause menu"
    return 0
fi