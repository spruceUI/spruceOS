#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

case "$(/mnt/SDCARD/spruce/scripts/bluetooth.sh forget-all)" in
    ok) log_and_display_message "All Bluetooth devices forgotten." ;;
    *"bluetooth is off") log_and_display_message "Turn Bluetooth on first." ;;
    *) log_and_display_message "Some Bluetooth devices could not be forgotten. See spruce.log." ;;
esac
