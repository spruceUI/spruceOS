#!/bin/sh

# This script read button input and print to STDOUT
# Please DO NOT PRINT ANYTHING ELSE TO STDOUT for logging !!

BIN_PATH="/mnt/SDCARD/spruce/bin"

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

( $BIN_PATH/getevent /dev/input/event3 -pid $$ & ) | while read line; do
    case $line in
        *"key 1 57 1"*) [ ! -z "$A" ] && echo -n "A" && break ;;
        *"key 1 29 1"*) [ ! -z "$B" ] && echo -n "B" && break ;;
        *"key 1 42 1"*) [ ! -z "$X" ] && echo -n "X" && break ;;
        *"key 1 56 1"*) [ ! -z "$Y" ] && echo -n "Y" && break ;;

        *"key 1 15 1"*) [ ! -z "$L1" ] && echo -n "L1" && break ;;
        *"key 1 18 1"*) [ ! -z "$L2" ] && echo -n "L2" && break ;;
        *"key 1 14 1"*) [ ! -z "$R1" ] && echo -n "R1" && break ;;
        *"key 1 20 1"*) [ ! -z "$R2" ] && echo -n "R2" && break ;;

        *"key 1 105 1"*) [ ! -z "$LEFT" ] && echo -n "LEFT" && break ;;
        *"key 1 106 1"*) [ ! -z "$RIGHT" ] && echo -n "RIGHT" && break ;;
        *"key 1 103 1"*) [ ! -z "$UP" ] && echo -n "UP" && break ;;
        *"key 1 108 1"*) [ ! -z "$DOWN" ] && echo -n "DOWN" && break ;;

        *"key 1 28 1"*) [ ! -z "$START" ] && echo -n "START" && break ;;
        *"key 1 97 1"*) [ ! -z "$SELECT" ] && echo -n "SELECT" && break ;;

        *"key 1 1 1"*) [ ! -z "$MENU" ] && echo -n "MENU" && break ;;
        *"key 1 115 1"*) [ ! -z "$VOLUMN_UP" ] && echo -n "VOLUMN_UP" && break ;;
        *"key 1 114 1"*) [ ! -z "$VOLUMN_DOWN" ] && echo -n "VOLUMN_DOWN" && break ;;
    esac
done

exit 0
