#!/bin/sh

# Update RAOfflineProxy from its own GitHub releases, so a fix on their side
# does not have to wait for a spruce release.
#
# The download and the unpacking are the app's own install-update, which is
# python and uses zipfile - the A30 and the Mini have no unzip.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

if ! ra_proxy_is_installed; then
    log_and_display_message "RAOfflineProxy is not installed."
    exit 1
fi

if ! network_is_connected true; then
    log_and_display_message "No network connection. Connect to WiFi and try again."
    exit 1
fi

log_and_display_message "Checking for a RAOfflineProxy update..."

OUT="$(_ra_proxy_run install-update --platform spruce --json 2>&1)"
RC=$?

# install-update stops the service itself; put it back the way the toggle says.
raproxy_apply

MSG="$(printf '%s\n' "$OUT" | tail -n 1)"
VERSION="$(printf '%s' "$MSG" | jq -r '.version // empty' 2>/dev/null)"

if [ "$RC" = "0" ] && [ -n "$VERSION" ]; then
    log_and_display_message "RAOfflineProxy updated to $VERSION."
else
    log_message "RAOfflineProxy update failed: $OUT"
    log_and_display_message "RAOfflineProxy is up to date, or the update failed. See spruce.log."
fi
