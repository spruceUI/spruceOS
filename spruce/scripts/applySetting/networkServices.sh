#!/bin/sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

# Define process to pretty name mapping
get_pretty_name() {
    case "$1" in
        "samba") echo "Samba" ;;
        "sftpgo") echo "WiFi File Transfer" ;;
        "syncthing") echo "Syncthing" ;;
        "dropbear") echo "SSH" ;;
        *) echo "$1" ;;
    esac
}

# Check if argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <process_name>"
    exit 1
fi

PROCESS="$1"
PRETTY_NAME=$(get_pretty_name "$PROCESS")
STATUS=$(quick_check "$PROCESS" && echo "On" || echo "Off")

echo -n "$PRETTY_NAME: $STATUS"
