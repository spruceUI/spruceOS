#!/bin/sh
# GameMT E5 Plus: switch the light rings round both sticks on or off, one
# press each way. The choice lives in /etc/e5plus-lights (dArkMoss), whose
# e5plus-lights.service reapplies it at boot.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HELPER=/usr/local/bin/e5plus-lights.sh
STATE=/etc/e5plus-lights

if [ "$(cat "$STATE" 2>/dev/null)" = "sticks-off" ]; then
    NEW=on;         VAL=1; MSG="Joystick lights on"
else
    NEW=sticks-off; VAL=0; MSG="Joystick lights off"
fi

if [ -x "$HELPER" ]; then
    "$HELPER" "$NEW"
else
    for l in left_joystick right_joystick; do
        echo "$VAL" > "/sys/class/leds/$l/brightness" 2>/dev/null
    done
    echo "$NEW" > "$STATE" 2>/dev/null
    sync
fi
log_message "Joystick Lights: $NEW"

/mnt/SDCARD/App/PyUI/launch.sh -msgDisplay "$MSG" -msgDisplayTimeMs 2000
