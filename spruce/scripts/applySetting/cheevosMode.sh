#!/bin/sh
# Usage: cheevosMode.sh <Manual|Disabled|Casual|Hardcore>
# Switching to Hardcore turns RAOfflineProxy off: the proxy can't validate a hardcore run.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

[ "$1" = "Hardcore" ] || exit 0
[ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" = "True" ] || exit 0

raproxy_setting_off || exit 0
log_message "cheevosMode: Hardcore, RAOfflineProxy turned off"
sh /mnt/SDCARD/spruce/scripts/applySetting/networkServiceToggle.sh raproxy False
