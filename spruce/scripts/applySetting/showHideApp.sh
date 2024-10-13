#!/bin/sh

check_app_visibility() {
    config_file="$1"
    if grep -q '"#label"' "$config_file"; then
        echo -n "off"
    else
        echo -n "on"
    fi
}

toggle_app_visibility() {
    config_file="$1"
    action="$2"
    
    if [ "$action" = "show" ]; then
        sed -i 's|"#label"|"label"|' "$config_file"
    elif [ "$action" = "hide" ]; then
        sed -i 's|"label"|"#label"|' "$config_file"
    fi
}

if [ "$1" = "check" ] && [ -n "$2" ]; then
    check_app_visibility "$2"
elif [ "$1" = "show" ] || [ "$1" = "hide" ] && [ -n "$2" ]; then
    toggle_app_visibility "$2" "$1"
else
    echo "Usage: $0 [check|show|hide] /path/to/config.json"
    exit 1
fi