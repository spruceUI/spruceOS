#!/bin/sh
# The one way to change the WiFi radio. PyUI and every shell path call this
# instead of enable_wifi/disable_wifi, so radio changes run one at a time.
#
# Usage: wifi.sh <command> [request file] [--wait]
#   apply         make the radio match the saved .wifi setting
#   restart       off and on again, only if the setting is on
#   suspend       radio off without changing the setting (sleep, in-game, poweroff)
#   connect FILE  save the network in FILE (/tmp/wifi_connect.*: SSID line, then
#                 password line or none), then apply
#   forget-all    clear saved networks, then apply
#   status        print state lines; takes no lock
#
# Returns at once and does the work in a detached copy, unless --wait.

WIFI_LOCK="/tmp/spruce_wifi.lock"
WIFI_STATE_FILE="/tmp/wifi_state"
WIFI_SUSPENDED="/tmp/wifi_suspended"
WIFI_LATEST_APPLY="/tmp/wifi_latest_apply"

CMD="$1"
[ $# -gt 0 ] && shift
ARG=""
WAIT=0
WORKER=0
for _a in "$@"; do
    case "$_a" in
        --wait) WAIT=1 ;;
        --worker) WORKER=1 ;;
        *) ARG="$_a" ;;
    esac
done

case "$CMD" in
    apply|restart|suspend|connect|forget-all|status) ;;
    *)
        echo "usage: wifi.sh apply|restart|suspend|connect FILE|forget-all|status [--wait]" >&2
        exit 1
        ;;
esac

# Hand off before sourcing helperFunctions, so PyUI and game exit get control back at once.
# Re-exec rather than a ( ) & subshell: the lock records $$, which a subshell shares with its parent.
if [ "$CMD" != "status" ] && [ "$WAIT" = 0 ] && [ "$WORKER" = 0 ]; then
    sh "$0" "$CMD" ${ARG:+"$ARG"} --worker </dev/null >/dev/null 2>&1 &
    exit 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$CMD" = "status" ]; then
    echo "state=$(cat "$WIFI_STATE_FILE" 2>/dev/null)"
    echo "setting=$(wifi_setting_wanted && echo 1 || echo 0)"
    echo "suspended=$([ -e "$WIFI_SUSPENDED" ] && echo 1 || echo 0)"
    echo "busy=$([ -d "$WIFI_LOCK" ] && echo 1 || echo 0)"
    exit 0
fi

wifi_sh_is_running() {
    [ -n "$1" ] && grep -q "wifi.sh" "/proc/$1/cmdline" 2>/dev/null
}

[ "$CMD" = "apply" ] && echo "$$" > "$WIFI_LATEST_APPLY"

# Half-second ticks. Sleep entry can't wait out a long SDIO recovery.
case "$CMD" in
    suspend) max_ticks=60 ;;
    *)       max_ticks=600 ;;
esac

ticks=0
empty_pid_ticks=0
locked=0
while :; do
    if mkdir "$WIFI_LOCK" 2>/dev/null; then
        locked=1
        break
    fi
    holder="$(cat "$WIFI_LOCK/pid" 2>/dev/null)"
    if [ -z "$holder" ]; then
        # The holder writes its pid just after mkdir; only an empty pid that stays empty is stale
        empty_pid_ticks=$((empty_pid_ticks + 1))
        if [ "$empty_pid_ticks" -gt 4 ]; then
            log_message "wifi.sh: clearing a lock with no holder"
            rm -rf "$WIFI_LOCK"
            continue
        fi
    elif ! wifi_sh_is_running "$holder"; then
        log_message "wifi.sh: clearing stale lock from $holder"
        rm -rf "$WIFI_LOCK"
        continue
    else
        empty_pid_ticks=0
    fi
    ticks=$((ticks + 1))
    [ "$ticks" -ge "$max_ticks" ] && break
    sleep 0.5
done

if [ "$locked" = 1 ]; then
    echo "$$" > "$WIFI_LOCK/pid"
    trap 'rm -rf "$WIFI_LOCK"' EXIT
    trap 'exit 143' INT TERM
elif [ "$CMD" = "suspend" ]; then
    log_message "wifi.sh: suspend could not get the lock from $(cat "$WIFI_LOCK/pid" 2>/dev/null); turning the radio off anyway"
else
    log_message "wifi.sh: gave up waiting for the lock ($CMD)"
    exit 1
fi

# Toggles that queued up behind a slow bring-up only need the last one to run
if [ "$CMD" = "apply" ]; then
    latest="$(cat "$WIFI_LATEST_APPLY" 2>/dev/null)"
    if [ "$latest" != "$$" ] && wifi_sh_is_running "$latest"; then
        log_message "wifi.sh: a newer apply is queued, skipping this one" -v
        exit 0
    fi
fi

record_state() {
    echo "$1" > "$WIFI_STATE_FILE" 2>/dev/null
}

bring_radio_up() {
    if enable_wifi; then
        record_state on
        return 0
    fi
    if wifi_available_on_device; then
        record_state failed
    else
        record_state no_radio
    fi
    return 1
}

apply_setting() {
    rm -f "$WIFI_SUSPENDED" 2>/dev/null
    if ! wifi_available_on_device; then
        record_state no_radio
        log_message "wifi.sh: no radio on this device, nothing to apply" -v
        return 0
    fi
    if wifi_setting_wanted; then
        bring_radio_up
        return
    fi
    was_on=0
    [ -f /tmp/wifion ] && was_on=1
    disable_wifi
    record_state off
    if [ "$was_on" = 1 ]; then
        sh /mnt/SDCARD/spruce/scripts/networkservices.sh off </dev/null >/dev/null 2>&1 &
    fi
}

restart_radio() {
    if ! wifi_setting_wanted || [ -e "$WIFI_SUSPENDED" ]; then
        return 0
    fi
    log_message "wifi.sh: restarting WiFi"
    disable_wifi
    sleep 1
    bring_radio_up
}

suspend_radio() {
    touch "$WIFI_SUSPENDED"
    wifi_available_on_device || return 0
    disable_wifi
    record_state off
}

connect_network() {
    case "$ARG" in
        /tmp/wifi_connect.*) ;;
        *)
            log_message "wifi.sh: connect needs a /tmp/wifi_connect.* request file"
            return 1
            ;;
    esac
    if [ ! -f "$ARG" ]; then
        log_message "wifi.sh: connect request $ARG is missing"
        return 1
    fi
    ssid=""
    psk=""
    {
        IFS= read -r ssid
        IFS= read -r psk
    } < "$ARG"
    rm -f "$ARG"
    if [ -z "$ssid" ]; then
        log_message "wifi.sh: connect request had no SSID"
        return 1
    fi
    if device_wifi_connect "$ssid" "$psk"; then
        log_message "wifi.sh: saved network $ssid"
    else
        log_message "wifi.sh: could not save network $ssid"
    fi
    psk=""
    apply_setting
}

forget_networks() {
    device_wifi_forget_all
    log_message "Wifi: All networks forgotten by request of user."
    apply_setting
}

case "$CMD" in
    apply)      apply_setting ;;
    restart)    restart_radio ;;
    suspend)    suspend_radio ;;
    connect)    connect_network ;;
    forget-all) forget_networks ;;
esac
exit 0
