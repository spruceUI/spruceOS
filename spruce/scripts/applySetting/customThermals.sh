#!/bin/sh
# Apply thermal control setting change immediately.
# Called when the user changes the Thermal Control option in System Settings.
# The thermal-watchdog picks up profile changes via inotify on active_profile.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

THERMAL_PROFILE_DIR="/mnt/SDCARD/spruce/smartpros/etc/thermal-watchdog"

selected="$(get_config_value '.menuOptions."System Settings".customThermals.selected' "Adaptive")"
profile=$(echo "$selected" | tr 'A-Z' 'a-z')

echo "$profile" > "$THERMAL_PROFILE_DIR/active_profile"

# Start watchdog if not already running
if ! pgrep -x thermal-watchdog >/dev/null 2>&1; then
    /mnt/SDCARD/spruce/smartpros/bin/thermal-watchdog &
fi
