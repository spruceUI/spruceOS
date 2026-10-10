#!/bin/sh
# The one way to change or read Bluetooth. PyUI and every shell path call this.
#
# Installed on PATH as spruce_bluetooth (spruce/scripts/bin).
# App/PyUI/bluetooth_readme.txt is the contract PyUI is written against; keep
# it in step with this file.
#
# Usage: bluetooth.sh <command> [address]
#   apply     make the radio match the saved .bluetooth setting
#   boot      apply once WiFi has connected (WiFi first on shared radios)
#   suspend   disconnect everything, without changing the setting (poweroff)
#   status    key=value lines: radio, setting, state, connected, connected_icon, audio
#   scan      look for devices for a few seconds, then list them
#   devices   list the devices known now, without looking
#   pair      pair, trust and connect <address>; prints "ok" or "failed <step> <reason>"
#   forget    remove <address>; prints "ok" or "failed forget <reason>"
#   disconnect  disconnect <address>, keeping the pairing; prints "ok" or "failed disconnect <reason>"
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

# Devices the user disconnected since the radio came on. reconnect_trusted
# leaves them alone until they are connected again or the radio restarts.
USER_DISCONNECTED=/tmp/bluetooth_user_disconnected

# Headsets that stayed on while the radio was down will not call back on
# their own, and right after boot the first attempt can come too early.
reconnect_pending() {
    timeout 5 bluetoothctl devices 2>/dev/null | while read -r _ mac _; do
        grep -qix "$mac" "$USER_DISCONNECTED" 2>/dev/null && continue
        case "$(timeout 5 bluetoothctl info "$mac" 2>/dev/null)" in
            *"Paired: yes"*"Trusted: yes"*"Connected: no"*) echo "$mac" ;;
        esac
    done
}

reconnect_trusted() {
    _try=1
    while [ "$_try" -le 6 ]; do
        _pending="$(reconnect_pending)"
        # Straight after a bluetoothd (re)start the device list can still be empty.
        if [ -z "$_pending" ] && [ -n "$(timeout 5 bluetoothctl devices 2>/dev/null)" ]; then
            return 0
        fi
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

# BlueZ's Connected, which asound-setup.sh routes on, not the radio link: the
# link comes up seconds earlier.
connections() {
    list_devices | awk 'BEGIN { FS = "\t" } $3 == 1 { print $1 }'
}

# PyUI reads $HOME/.asoundrc and reopens its output when the flag appears.
route_audio() {
    /mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
    touch /tmp/audio_reinit_needed
}

# Routing follows the links, not the commands: a change is acted on once it has held
# for one poll, as the audio profile comes up just after the link.
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

# Powering the adapter off sends each device a proper disconnect, as a phone
# does; killing the daemons only drops the link.
disconnect_all() {
    bt_running && timeout 5 bluetoothctl power off >/dev/null 2>&1
}

# Pairable does not survive a daemon restart, and a pairing made without it
# is not kept.
apply_setting() {
    device_bluetooth_supported || return 0
    if [ "$(bt_setting)" = "1" ]; then
        rm -f "$USER_DISCONNECTED"
        if ! device_bluetooth_up; then
            # e.g. a combo chip whose WiFi half is off: say so rather than
            # powering on a controller or a daemon that is not there.
            log_message "bluetooth.sh: on, but the radio did not come up" >/dev/null
            device_bluetooth_down
            return 1
        fi
        timeout 10 bluetoothctl power on >/dev/null 2>&1
        timeout 10 bluetoothctl pairable on >/dev/null 2>&1
        log_message "bluetooth.sh: on" >/dev/null
        stop_watch
        # A subshell that drops its descriptors: "func >/dev/null &" keeps the
        # caller's stdout and stderr open as saved descriptors, so a caller
        # that reads them (PyUI) would wait for the watcher, which never ends.
        ( exec </dev/null >/dev/null 2>&1; watch_connections ) &
        echo $! > "$WATCH_PID"
        ( exec </dev/null >/dev/null 2>&1; reconnect_trusted ) &
    else
        stop_watch
        disconnect_all
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
    icons=""
    if bt_running; then
        state=on
        _connected="$(list_devices | awk 'BEGIN { FS = "\t" } $3 == 1')"
        connected="$(printf '%s\n' "$_connected" | head -n 1 | cut -f4)"
        for _mac in $(printf '%s\n' "$_connected" | cut -f1); do
            _icon="$(timeout 5 bluetoothctl info "$_mac" 2>/dev/null | sed -n 's/^[[:space:]]*Icon: //p' | head -n 1)"
            icons="${icons:+$icons,}${_icon:-unknown}"
        done
    fi
    audio=0
    [ "$state" = on ] && bt_audio_ready && audio=1
    printf 'radio=%s\nsetting=%s\nstate=%s\nconnected=%s\nconnected_icon=%s\naudio=%s\n' \
        "$radio" "$(bt_setting)" "$state" "$connected" "$icons" "$audio"
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
    if [ -f "$USER_DISCONNECTED" ]; then
        grep -vix "$mac" "$USER_DISCONNECTED" > "$USER_DISCONNECTED.tmp" 2>/dev/null
        mv "$USER_DISCONNECTED.tmp" "$USER_DISCONNECTED"
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
        *"org.bluez.Error.InProgress"*)
            # reconnect_trusted is connecting it already: wait for that.
            _n=0
            until timeout 5 bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; do
                _n=$((_n + 1))
                [ "$_n" -le 15 ] || { pair_failed connect "$out"; return; }
                sleep 1
            done
            ;;
        *) pair_failed connect "$out"; return ;;
    esac

    device_bt_audio_connected
    log_message "bluetooth.sh: connected a device" >/dev/null
    echo "ok"
}

forget_device() {
    if [ -z "$1" ] || ! bt_running; then
        echo "failed forget bluetooth is off"
        return
    fi
    out="$(timeout 10 bluetoothctl remove "$1" 2>&1)"
    case "$out" in
        *"Device has been removed"*) ;;
        *) pair_failed forget "$out"; return ;;
    esac
    route_audio >/dev/null 2>&1
    echo "ok"
}

disconnect_device() {
    if [ -z "$1" ] || ! bt_running; then
        echo "failed disconnect bluetooth is off"
        return
    fi
    # Hold it first, so reconnect_trusted cannot bring it straight back.
    echo "$1" >> "$USER_DISCONNECTED"
    out="$(timeout 10 bluetoothctl disconnect "$1" 2>&1)"
    case "$out" in
        # BlueZ 5.82 says "Disconnection successful"; older ones the other.
        *"Successful disconnected"*|*"Disconnection successful"*) ;;
        *) pair_failed disconnect "$out"; return ;;
    esac
    route_audio >/dev/null 2>&1
    echo "ok"
}

# WiFi goes first: on combo chips Bluetooth traffic can keep it from joining.
# Give up after a minute so Bluetooth still comes on without a network.
wait_for_wifi() {
    _n=0
    while [ "$_n" -lt 60 ]; do
        case "$(/mnt/SDCARD/spruce/scripts/wifi.sh status 2>/dev/null | sed -n 's/^link=//p')" in
            connecting) ;;
            *) return 0 ;;
        esac
        sleep 1
        _n=$((_n + 1))
    done
}

case "$1" in
    apply)   apply_setting ;;
    boot)
        # Before PyUI starts: it reads .asoundrc once.
        /mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME" >/dev/null 2>&1
        device_bluetooth_supported && wait_for_wifi
        apply_setting ;;
    suspend) device_bluetooth_supported && disconnect_all ;;
    status)  show_status ;;
    scan)    scan_devices ;;
    devices) list_devices ;;
    pair)    pair_device "$2" ;;
    forget)  forget_device "$2" ;;
    disconnect) disconnect_device "$2" ;;
    *)       echo "usage: bluetooth.sh apply|boot|suspend|status|scan|devices|pair <address>|forget <address>|disconnect <address>" >&2; exit 2 ;;
esac
