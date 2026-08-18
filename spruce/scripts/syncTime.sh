#!/bin/sh

# Sync the clock now, out of band.
#
# networkservices.sh already syncs when it runs - at boot once WiFi is up, and
# on every return to the menu from a game - but neither of those fires when the
# user is sitting in Settings. Turning "Sync Time via Network" on there should
# take effect there and then rather than at the next game exit, so the menu
# launches this detached.
#
# sync_system_time does all the deciding: it honours the toggle, returns
# immediately when the clock is already sane, and logs what it did. This is
# only a way in from outside the shell.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/timeFunctions.sh

sync_system_time
exit 0
