#!/bin/sh
# usb_wifi_watchdog.sh - hot-plug watcher for USB WiFi dongles on devices whose
# platform cfg sets WIFI_USB_MODULES_DIR (the TrimUI A133P line today).
#
# The USB bus knows about a dongle seconds after it is plugged in; nothing in
# spruce would notice until the next enable_wifi (a game exit or the WiFi
# toggle). This watchdog polls /sys/bus/usb/devices every POLL_INTERVAL seconds
# - one directory listing, no driver work - and calls usb_wifi_hotplug_event
# (utils/usb_wifi_dongle.sh) on every change: arrival swaps the onboard radio
# for the dongle when WiFi is on, removal puts the onboard radio back. The
# heavy lifting and every decision live in the contract; this loop only
# detects edges. It also covers the boot race: the boot-time enable_wifi runs
# before a dongle plugged in at power-on has enumerated, so the first tick
# that sees it does the swap.
#
# Launched by launch_trimui_startup_watchdogs (pinned like the others); a
# device without WIFI_USB_MODULES_DIR exits at once.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

[ -n "$WIFI_USB_MODULES_DIR" ] || exit 0
command -v usb_wifi_dongle_present >/dev/null 2>&1 || exit 0

POLL_INTERVAL="${USB_WIFI_POLL_INTERVAL:-2}"
STOP_FILE=/tmp/usb_wifi_watchdog-stop

log_message "usb_wifi_watchdog.sh: started (modules in $WIFI_USB_MODULES_DIR, poll ${POLL_INTERVAL}s)"
rm -f "$STOP_FILE" 2>/dev/null

last="$(usb_wifi_dongle_present 2>/dev/null)" || last=""
[ -n "$last" ] && log_message "usb_wifi_watchdog.sh: dongle $last already on the bus"

while [ ! -e "$STOP_FILE" ]; do
    sleep "$POLL_INTERVAL"
    cur="$(usb_wifi_dongle_present 2>/dev/null)" || cur=""
    [ "$cur" = "$last" ] && continue
    # The resume gap is not an unplug: while the wake hook is waiting for the
    # dongle to re-enumerate (usb_wifi_wait_after_resume owns that decision),
    # an empty bus is "not back yet". The marker goes away when it decides.
    if [ -z "$cur" ] && [ -e "$WIFI_USB_DONGLE_SLEEPING" ]; then
        continue
    fi
    if [ -n "$cur" ]; then
        usb_wifi_hotplug_event arrived "$cur"
    else
        usb_wifi_hotplug_event removed "$last"
    fi
    last="$cur"
done
log_message "usb_wifi_watchdog.sh: stopped"
