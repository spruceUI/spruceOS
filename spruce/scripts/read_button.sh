#!/bin/sh

# This script read button input and print to STDOUT
# Please DO NOT PRINT ANYTHING ELSE TO STDOUT for logging !!

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** homebutton_watchdog.sh: helperFunctions imported." -v

BIN_PATH="/mnt/SDCARD/spruce/bin64"
if [ "$PLATFORM" = "A30"]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin"
    TRIGGER_DOWN="1"
else
    TRIGGER_DOWN="255"
fi

DOWN=1
if [ $PLATFORM]
if [ "$#" -eq 0 ]; then
    A=true
    B=true
    X=true
    Y=true
    L1=true
    L2=true
    R1=true
    R2=true
    LEFT=true
    RIGHT=true
    UP=true
    DOWN=true
    START=true
    SELECT=true
    MENU=true
    VOLUMN_UP=true
    VOLUMN_DOWN=true
fi

for var in "$@"
do
    case "$var" in
        "A") A=true ;;
        "B") B=true ;;
        "X") X=true ;;
        "Y") Y=true ;;
        "L1") L1=true ;;
        "L2") L2=true ;;
        "R1") R1=true ;;
        "R2") R2=true ;;
        "LEFT") LEFT=true ;;
        "RIGHT") RIGHT=true ;;
        "UP") UP=true ;;
        "DOWN") DOWN=true ;;
        "START") START=true ;;
        "SELECT") SELECT=true ;;
        "MENU") MENU=true ;;
        "VOLUMN_UP") VOLUMN_UP=true ;;
        "VOLUMN_DOWN") VOLUMN_DOWN=true ;;
    esac
done

( $BIN_PATH/getevent -pid $$ $EVENT_PATH_READ_INPUTS_SPRUCE & ) | while read line; do
    case $line in
        *"key $B_A 1"*) [ ! -z "$A" ] && echo -n "A" && break ;;
        *"key $B_B 1"*) [ ! -z "$B" ] && echo -n "B" && break ;;
        *"key $B_X 1"*) [ ! -z "$X" ] && echo -n "X" && break ;;
        *"key$B_Y 1"*) [ ! -z "$Y" ] && echo -n "Y" && break ;;

        *"key $B_L1 1"*) [ ! -z "$L1" ] && echo -n "L1" && break ;;
        *"key $B_L2 $DOWN"*) [ ! -z "$L2" ] && echo -n "L2" && break ;;
        *"key $B_R1 1"*) [ ! -z "$R1" ] && echo -n "R1" && break ;;
        *"key $B_R2 $DOWN"*) [ ! -z "$R2" ] && echo -n "R2" && break ;;

        *"key $B_LEFT"*) [ ! -z "$LEFT" ] && echo -n "LEFT" && break ;;
        *"key $B_RIGHT"*) [ ! -z "$RIGHT" ] && echo -n "RIGHT" && break ;;
        *"key $B_UP"*) [ ! -z "$UP" ] && echo -n "UP" && break ;;
        *"key $B_DOWN"*) [ ! -z "$DOWN" ] && echo -n "DOWN" && break ;;

        *"key $B_START 1"*) [ ! -z "$START" ] && echo -n "START" && break ;;
        *"key $B_SELECT 1"*) [ ! -z "$SELECT" ] && echo -n "SELECT" && break ;;

        *"key $B_MENU 1"*) [ ! -z "$MENU" ] && echo -n "MENU" && break ;;
        *"key $B_VOLUP 1"*) [ ! -z "$VOLUMN_UP" ] && echo -n "VOLUMN_UP" && break ;;
        *"key $B_VOLDOWN 1"*) [ ! -z "$VOLUMN_DOWN" ] && echo -n "VOLUMN_DOWN" && break ;;
    esac
done

exit 0
