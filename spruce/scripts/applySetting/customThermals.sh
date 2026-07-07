#!/bin/sh
# Apply thermal control setting change immediately.
# Called when the user changes the Thermal Control option in System Settings.

exec /mnt/SDCARD/spruce/smartpros/bin/update-thermal-watchdog-to-setting "$@"
