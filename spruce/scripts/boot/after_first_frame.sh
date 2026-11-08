#!/bin/sh
# Boot work that doesn't need to beat the menu: the WiFi bring-up and RAOfflineProxy.
# Started beside PyUI, they slow its first frame, most on two-core devices like the Mini.
#
# PyUI runs this after every first frame (firstFrameCmd in App/PyUI/py-ui-config.json).
# runtime.sh runs it straight away on boots that don't show the menu first, and again
# after a timeout in case PyUI never draws. Only the first call of a boot does anything.

# miyoo_mini_startup.sh waits for this directory before its own WiFi bring-up
mkdir /tmp/spruce_boot_jobs_started 2>/dev/null || exit 0

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

log_message "Starting WiFi and RAOfflineProxy (${1:-first frame})"
# The proxy goes first: on boots without the menu a game follows at once, and RetroArch
# logs in to it. Not gated on WiFi, since achievements are earned offline.
# Backgrounded: stopping a disabled proxy runs its Python backend.
raproxy_apply &
wifi_request apply
