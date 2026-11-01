#!/bin/sh
# Runs an app's launch script for PyUI, which stays up and shows the script's messages
# (App/PyUI/main-ui/apps/script_app.py, for apps with "launchInPyUI": true):
#
#   run_app_in_pyui.sh <app folder> <launch script>
#
# Does for the script what principal.sh does for a command it runs once PyUI exits: activity
# tracking, the user's time zone, no output, and afterwards the idle shutdown, which these
# scripts stop while they work. PyUI starts this with principal.sh's environment and
# PYUI_HOSTS_MESSAGES set, so start_pyui_message_writer leaves the socket to the menu.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

folder="$1"
launch="$2"
cd "$folder" || exit 1
case "$launch" in
    /*) ;;
    *) launch="./$launch" ;;
esac
chmod a+x "$launch"

log_message "Running $launch inside PyUI"
log_activity_event "$launch" "START"
_tz="$(jq -r '.timezone // empty' /mnt/SDCARD/Saves/spruce/shared-system.json 2>/dev/null)"
if [ -n "$_tz" ] && [ -f "/mnt/SDCARD/spruce/zoneinfo/$_tz" ]; then
    TZ=":/mnt/SDCARD/spruce/zoneinfo/$_tz" "$launch" >/dev/null 2>&1
else
    "$launch" >/dev/null 2>&1
fi
status=$?
log_activity_event "$launch" "STOP"
log_message "$launch exited with status $status; back in PyUI"

# principal.sh does this after every command: the script may have stopped idlemon.
/mnt/SDCARD/spruce/scripts/idle_watchdog.sh >/dev/null 2>&1 &
exit "$status"
