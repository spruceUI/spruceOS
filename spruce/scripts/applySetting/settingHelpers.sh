#!/bin/sh

CFG_FILE="/mnt/SDCARD/spruce/settings/spruce.cfg"

quick_check() {
    [ $# -eq 1 ] || return 1
    value=$(grep "^$1=" "$CFG_FILE" | cut -d'=' -f2 | tr -d '\r\n')
    if [ -z "$value" ]; then
        return 1
    else
       return "$value"
    fi
}

update_setting() {
    [ $# -eq 2 ] || return 1
    key="$1"
    value="$2"

    case "$value" in
    "on" | "true" | "1") value=0 ;;
    "off" | "false" | "0") value=1 ;;
    esac

    if grep -q "^$key=" "$CFG_FILE"; then
        sed -i "s/^$key=.*/$key=$value/" "$CFG_FILE"
    else
        # Ensure there's a newline at the end of the file before appending
        sed -i -e '$a\' "$CFG_FILE"
        echo "$key=$value" >>"$CFG_FILE"
    fi
}

# Check if arguments are provided and run smart helpers
if [ $# -eq 2 ] && [ "$1" = "check" ]; then
    if quick_check "$2"; then
        echo -n "on"
    else
        echo -n "off"
    fi
elif [ $# -eq 3 ] && [ "$1" = "get" ]; then
    value=$(grep "^$2=" "$CFG_FILE" | cut -d'=' -f2 | tr -d '\r\n')
    if [ -z "$value" ]; then
        echo -n "$3"
    else
        echo -n "$value"
    fi
elif [ $# -eq 3 ] && [ "$1" = "update" ]; then
    update_setting "$2" "$3"
fi
