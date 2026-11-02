#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

case "$1" in
    battery_percent|wifi_radio)
        ;;
    *)
        echo "Usage: $0 {battery_percent|wifi_radio}" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

# battery_percent prints the device's reading; wifi_radio answers in its exit status.
case "$1" in
    battery_percent) device_get_battery_percent ;;
    wifi_radio) wifi_available_on_device ;;
esac
