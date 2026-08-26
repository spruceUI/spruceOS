#!/bin/sh
# Switch scene action: turn WiFi on/off through spruce's own WiFi system.
#
# trimui_scened runs this with arg 1 (switch on -> WiFi off) / 0 (switch off ->
# WiFi back on). Goes through the same enable_wifi / disable_wifi that boot,
# sleep, and Settings -> Network Settings -> WiFi already use, and keeps .wifi
# in SYSTEM_JSON in sync (the same pattern set_backlight uses for .backlight)
# so the WiFi menu, the top bar icon, and anything else that reads .wifi (e.g.
# handle_network_services) agree with the state the switch put the radio in.
#
# Unlike the Brick (whose switch draws its own on-screen toast), the Smart Pro S
# switch has no popup, so the WiFi menu / top bar icon is the only feedback the
# user gets that the switch did something.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_wifi_config_value() {
    tmp="$(mktemp)"
    jq ".wifi = $1" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON"
}

case "$1" in
    1)
        set_wifi_config_value 0
        disable_wifi
        ;;
    0)
        set_wifi_config_value 1
        enable_wifi
        ;;
esac
