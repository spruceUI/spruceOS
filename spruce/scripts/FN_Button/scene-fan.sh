#!/bin/sh
# Switch action: fan one profile above Fan Speed while on (1), back to it when
# off (0). The setting itself is never changed.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

THERMAL_CMD="/mnt/SDCARD/spruce/smartpros/bin/update-thermal-watchdog-to-setting"

# Adaptive has no fixed level to step from.
boosted_profile() {
    case "$1" in
        "Off")    echo "Low" ;;
        "Low")    echo "Medium" ;;
        *)        echo "High" ;;
    esac
}

case "$1" in
    1)
        setting="$(get_config_value '.menuOptions."System Settings".customThermals.selected' "Adaptive")"
        "$THERMAL_CMD" "$(boosted_profile "$setting")"
        ;;
    0)
        "$THERMAL_CMD"
        ;;
esac
