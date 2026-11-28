#!/bin/sh
# changeCmd of Settings > Network Settings > Device name (hostnameSource, passes the chosen
# source as $1) and Custom device name (hostname, passes "name" then what was typed). PyUI has
# already saved the value. Applies the resulting name as the hostname and the <name>.local name.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/hostnameFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/mdnsFunctions.sh

SPRUCE_CFG=/mnt/SDCARD/Saves/spruce/spruce-config.json
HOSTNAME_PATH='.menuOptions."Network Settings".hostname.selected'

# Custom device name only: put the normalised name in place of what was typed, so the setting
# shows what is really used (empty when nothing valid remains, which means the model default).
if [ "$1" = name ]; then
    typed="$(normalize_hostname "$2")"
    if [ "$typed" != "$2" ]; then
        jq --arg name "$typed" "$HOSTNAME_PATH = \$name" "$SPRUCE_CFG" >"$SPRUCE_CFG.tmp" &&
            [ -s "$SPRUCE_CFG.tmp" ] && mv -f "$SPRUCE_CFG.tmp" "$SPRUCE_CFG"
        rm -f "$SPRUCE_CFG.tmp"
    fi
fi

name="$(get_spruce_hostname)"
log_message "hostname: device name is now $name"
device_set_hostname "$name"
echo "$name" >"$HOSTNAME_STATE_FILE"

# Only a running responder needs telling; it announces the new name when restarted.
# No network check here: this runs on PyUI's UI thread, and the restart's sync checks the link.
mdns_is_running && restart_mdns_process
exit 0
