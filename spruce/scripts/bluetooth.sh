#!/bin/sh
# The one way to change or read Bluetooth. PyUI and every shell path call this.
#
# Installed on PATH as spruce_bluetooth (spruce/scripts/bin).
# App/PyUI/bluetooth_readme.txt is the contract PyUI is written against; keep
# it in step with this file.
#
# Usage: bluetooth.sh <command> [address]
#   apply     make the radio match the saved .bluetooth setting
#   status    key=value lines: radio, setting, state, connected
#   scan      look for devices for a few seconds, then list them
#   devices   list the devices known now, without looking
#   pair      pair, trust and connect <address>; prints "ok" or "failed <step> <reason>"
#   forget    remove <address>
#
# scan and devices print one device per line, tab separated:
#   address    paired 0/1    connected 0/1    name

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SCAN_SECONDS=6

bt_setting() {
    jq -r '.bluetooth // 0' "$SYSTEM_JSON" 2>/dev/null
}

bt_running() {
    pidof bluetoothd >/dev/null 2>&1
}

# Headsets that stayed on while the radio was down will not call back on
# their own, and right after boot the first attempt can come too early.
reconnect_pending() {
    timeout 5 bluetoothctl devices 2>/dev/null | while read -r _ mac _; do
        case "$(timeout 5 bluetoothctl info "$mac" 2>/dev/null)" in
            *"Paired: yes"*"Trusted: yes"*"Connected: no"*) echo "$mac" ;;
        esac
    done
}

reconnect_trusted() {
    _try=1
    while [ "$_try" -le 6 ]; do
        _pending="$(reconnect_pending)"
        [ -n "$_pending" ] || return 0
        for mac in $_pending; do
            out="$(timeout 15 bluetoothctl connect "$mac" 2>&1)"
            case "$(timeout 5 bluetoothctl info "$mac" 2>/dev/null)" in
                *"Connected: yes"*) log_message "bluetooth.sh: reconnected a device (try $_try)" ;;
                *) [ "$_try" -eq 6 ] && log_message "bluetooth.sh: reconnect failed: $(bluez_error "$out")" ;;
            esac
        done
        _try=$((_try + 1))
        sleep 5
    done
}

connections() {
    if command -v hcitool >/dev/null 2>&1; then
        hcitool con 2>/dev/null | awk '/ACL/ { print $3 }'
    else
        list_devices | awk -F'\t' '$3 == 1 { print $1 }'
    fi
}

# PyUI reads $HOME/.asoundrc and reopens its output when the flag appears.
route_audio() {
    /mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
    touch /tmp/audio_reinit_needed
}

# Headsets connect and drop on their own, so the routing follows the links
# rather than the commands. A change is acted on once it has held for one
# poll, as the audio profile comes up a moment after the link.
WATCH_PID=/tmp/bluetooth_watch.pid

watch_connections() {
    _routed="-"
    _prev=""
    while bt_running; do
        _now="$(connections | sort | tr '\n' ' ')"
        if [ "$_now" != "$_routed" ] && [ "$_now" = "$_prev" ]; then
            route_audio
            _routed="$_now"
        fi
        _prev="$_now"
        sleep 3
    done
    rm -f "$WATCH_PID"
}

stop_watch() {
    [ -f "$WATCH_PID" ] && kill "$(cat "$WATCH_PID")" 2>/dev/null
    rm -f "$WATCH_PID"
}

# Pairable does not survive a daemon restart, and a pairing made without it
# is not kept.
apply_setting() {
    device_bluetooth_supported || return 0
    if [ "$(bt_setting)" = "1" ]; then
        device_bluetooth_up
        timeout 10 bluetoothctl power on >/dev/null 2>&1
        timeout 10 bluetoothctl pairable on >/dev/null 2>&1
        log_message "bluetooth.sh: on" >/dev/null
        stop_watch
        watch_connections >/dev/null 2>&1 &
        echo $! > "$WATCH_PID"
        reconnect_trusted >/dev/null 2>&1 &
    else
        stop_watch
        device_bluetooth_down
        route_audio >/dev/null 2>&1
        log_message "bluetooth.sh: off" >/dev/null
    fi
}

# A device that has not sent a name is listed under its address written with
# dashes. Nothing can be done with those, so they are left out.
list_devices() {
    bt_running || return 0
    timeout 5 bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
        case "$name" in
            ""|[0-9A-F][0-9A-F]-[0-9A-F][0-9A-F]-[0-9A-F][0-9A-F]-*) continue ;;
        esac
        info="$(timeout 5 bluetoothctl info "$mac" 2>/dev/null)"
        paired=0
        connected=0
        case "$info" in *"Paired: yes"*) paired=1 ;; esac
        case "$info" in *"Connected: yes"*) connected=1 ;; esac
        printf '%s\t%s\t%s\t%s\n' "$mac" "$paired" "$connected" "$name"
    done
}

# Discovery lasts only while the bluetoothctl that asked for it is running, so
# this has to hold one open rather than start a scan and return.
scan_devices() {
    bt_running || return 0
    bluetoothctl --timeout "$SCAN_SECONDS" scan on >/dev/null 2>&1
    list_devices
}

show_status() {
    radio=0
    device_bluetooth_supported && radio=1
    state=off
    connected=""
    if bt_running; then
        state=on
        connected="$(list_devices | awk -F'\t' '$3 == 1 { print $4; exit }')"
    fi
    printf 'radio=%s\nsetting=%s\nstate=%s\nconnected=%s\n' \
        "$radio" "$(bt_setting)" "$state" "$connected"
}

bluez_error() {
    _err="$(printf '%s\n' "$1" | sed -n 's/.*\(org\.bluez\.Error\.[A-Za-z.]*\).*/\1/p' | tail -n 1)"
    echo "${_err:-no answer}"
}

pair_failed() {
    _reason="$(bluez_error "$2")"
    log_message "bluetooth.sh: $1 failed: $_reason" >/dev/null
    printf '%s\n' "$2" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]/<address>/g' \
        | tail -n 6 > /tmp/bluetooth_last_failure 2>/dev/null
    echo "failed $1 $_reason"
}

pair_device() {
    mac="$1"
    _addr=missing
    [ -n "$mac" ] && _addr=given
    log_message "bluetooth.sh: pair requested (address $_addr, daemon $(bt_running && echo up || echo down))" >/dev/null
    if [ -z "$mac" ]; then
        echo "failed pair no address"
        return
    fi
    if ! bt_running; then
        echo "failed pair bluetooth is off"
        return
    fi

    case "$(timeout 5 bluetoothctl info "$mac" 2>/dev/null)" in
        *"Paired: yes"*) ;;
        *)
            out="$(timeout 40 bluetoothctl pair "$mac" 2>&1)"
            case "$out" in
                *"Pairing successful"*) ;;
                *) pair_failed pair "$out"; return ;;
            esac
            ;;
    esac

    timeout 10 bluetoothctl trust "$mac" >/dev/null 2>&1

    # Always: pairing leaves only the bare link up, which reads as connected
    # and then drops. connect is what brings up the audio profile.
    out="$(timeout 30 bluetoothctl connect "$mac" 2>&1)"
    case "$out" in
        *"Connection successful"*) ;;
        *) pair_failed connect "$out"; return ;;
    esac

    command -v device_bt_audio_connected >/dev/null 2>&1 && device_bt_audio_connected
    log_message "bluetooth.sh: connected a device" >/dev/null
    echo "ok"
}

forget_device() {
    [ -n "$1" ] && bt_running || return 0
    timeout 10 bluetoothctl remove "$1" >/dev/null 2>&1
}

case "$1" in
    apply)   apply_setting ;;
    status)  show_status ;;
    scan)    scan_devices ;;
    devices) list_devices ;;
    pair)    pair_device "$2" ;;
    forget)  forget_device "$2" ;;
    *)       echo "usage: bluetooth.sh apply|status|scan|devices|pair <address>|forget <address>" >&2; exit 2 ;;
esac
