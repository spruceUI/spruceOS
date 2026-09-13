#!/bin/sh
# Restarts WiFi when the setting is on, a network is saved, and wlan0 has had no
# IPv4 address for a minute: five restarts, then a ten minute pause. Never
# changes the setting. An address is enough - a LAN without internet or with
# ICMP blocked is not broken WiFi.
#
# Started by launch_common_startup_watchdogs_v2 where device_wifi_watchdog_enabled
# says so. Stands aside during sleep, in-game WiFi off, and any wifi.sh run.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

POLL_SECONDS=10
DOWN_SECONDS=60
RESTART_LIMIT=5
BACKOFF_SECONDS=600

# Uptime, not the clock: time sync jumps the clock by years on devices without an RTC
uptime_seconds() {
    cut -d. -f1 /proc/uptime
}

wlan0_has_ipv4() {
    if command -v ip >/dev/null 2>&1; then
        ip -4 -o addr show dev wlan0 2>/dev/null | grep -q "inet " && return 0
    fi
    ifconfig wlan0 2>/dev/null | grep -q "inet "
}

# A read error counts as a saved network: never give up on a guess
has_saved_network() {
    [ -r "$WPA_SUPPLICANT_FILE" ] || return 0
    grep -q '^[[:space:]]*network=' "$WPA_SUPPLICANT_FILE"
}

log_message "wifi_watchdog.sh: started"
last_ok="$(uptime_seconds)"
restarts=0

while :; do
    sleep "$POLL_SECONDS"
    now="$(uptime_seconds)"

    if ! wifi_setting_wanted; then
        last_ok="$now"
        restarts=0
        continue
    fi
    if [ -e /tmp/wifi_suspended ] || [ -e /tmp/sleep_helper_started ] || [ -d /tmp/spruce_wifi.lock ]; then
        last_ok="$now"
        continue
    fi
    if wlan0_has_ipv4 || ! has_saved_network; then
        last_ok="$now"
        restarts=0
        continue
    fi

    down=$((now - last_ok))
    if [ "$restarts" -lt "$RESTART_LIMIT" ]; then
        [ "$down" -gt "$DOWN_SECONDS" ] || continue
        restarts=$((restarts + 1))
        log_message "wifi_watchdog.sh: no address on wlan0 for ${down}s, restarting WiFi ($restarts/$RESTART_LIMIT)"
        last_ok="$now"
        wifi_request restart
    elif [ "$down" -gt "$BACKOFF_SECONDS" ]; then
        restarts=0
        last_ok="$now"
    fi
done
