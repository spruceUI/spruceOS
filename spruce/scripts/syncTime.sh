#!/bin/sh

# Sync the clock now, out of band.
#
# networkservices.sh already syncs when it runs - at boot once WiFi is up, and
# on every return to the menu from a game - but neither of those fires when the
# user is sitting in Settings. Turning "Sync Time via Network" on there should
# take effect there and then rather than at the next game exit, so the menu
# launches this detached.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/timeFunctions.sh

# This is the user asking, from Time Settings, so run both even if they already
# ran this boot.
sync_system_time --again
sync_timezone_from_network --again
exit 0
