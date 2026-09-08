#!/bin/sh
# Toggles the battery monitor daemon. Run once to start, again to stop.
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

PIDFILE=/tmp/battery_monitor.pid
LOG=/mnt/SDCARD/Saves/spruce/battery_monitor.csv
MON=/mnt/SDCARD/App/BatteryMonitor/monitor.sh

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    sync
    log_and_display_message "Battery monitor stopped. Log: Saves/spruce/battery_monitor.csv"
    sleep 3
    exit 0
fi

chmod +x "$MON"
# setsid so the daemon outlives this launcher and whatever PyUI does to its process group
if command -v setsid >/dev/null 2>&1; then
    setsid sh "$MON" >/dev/null 2>&1 </dev/null &
else
    nohup sh "$MON" >/dev/null 2>&1 </dev/null &
fi
sleep 1
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    log_and_display_message "Battery monitor started (15s samples). Run again to stop."
else
    log_and_display_message "Battery monitor failed to start"
fi
sleep 3
