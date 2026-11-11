#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

case "$1" in
    battery_percent|charge_status|wifi_radio)
        ;;
    *)
        echo "Usage: $0 {battery_percent|charge_status|wifi_radio}" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

# battery_percent and charge_status print readings; wifi_radio answers in its exit status.
case "$1" in
    battery_percent) device_get_battery_percent ;;
    charge_status)
        if [ "$(cat "$BATTERY/status" 2>/dev/null | tr '[:upper:]' '[:lower:]')" = "charging" ]; then
            echo "charging"
        else
            echo "disconnected"
        fi
        ;;
    wifi_radio) wifi_available_on_device ;;
esac
