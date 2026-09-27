#!/bin/sh
# The one way to change the WiFi radio. PyUI and every shell path call this
# instead of enable_wifi/disable_wifi, so radio changes run one at a time.
#
# Installed on PATH as spruce_wifi (spruce/scripts/bin). App/PyUI/wifi_readme.txt
# is the contract PyUI is written against; keep it in step with this file.
#
# Usage: wifi.sh <command> [request file] [--wait]
#   apply         make the radio match the saved .wifi setting
#   restart       off and on again, only if the setting is on
#   suspend       radio off without changing the setting (sleep, in-game, poweroff)
#   connect       save the network read from stdin (SSID line, then password
#                 line, or none for an open network), then apply. A shell caller
#                 may pass a /tmp/wifi_connect.* file holding those lines instead.
#   forget-all    clear saved networks, then apply
#
# Read-only commands answer at once and take no lock:
#   status        key=value lines: radio, setting, suspended, busy, state, link,
#                 ssid, freq, ip, signal, saved
#   ip            the IPv4 address of the WiFi interface, or nothing
#   saved         saved network names, one per line
#   scan          visible networks, one per line: ssid, signal dBm, MHz,
#                 secured 0/1, bssid, tab separated. Blocks a few seconds.
#
# Radio changes return at once and do the work in a detached copy, unless --wait.

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

READ_ONLY=0
case "$CMD" in
    apply|restart|suspend|connect|forget-all) ;;
    status|ip|saved|scan) READ_ONLY=1 ;;
    *)
        echo "usage: wifi.sh apply|restart|suspend|connect [FILE]|forget-all [--wait]" >&2
        echo "       wifi.sh status|ip|saved|scan" >&2
        exit 1
        ;;
esac

# connect: the network arrives on stdin (PyUI pipes two lines) and the hand-off
# below cuts stdin, so take it here into a private file for the worker. The
# worker reads that file and deletes it before it does anything else.
if [ "$CMD" = "connect" ] && [ -z "$ARG" ] && [ "$WORKER" = 0 ]; then
    ARG="/tmp/wifi_connect.$$"
    rm -f "$ARG"
    ( umask 077; cat > "$ARG" ) || exit 1
fi

# Hand off before sourcing helperFunctions, so PyUI and game exit get control back at once.
# Re-exec rather than a ( ) & subshell: the lock records $$, which a subshell shares with its parent.
if [ "$READ_ONLY" = 0 ] && [ "$WAIT" = 0 ] && [ "$WORKER" = 0 ]; then
    sh "$0" "$CMD" ${ARG:+"$ARG"} --worker </dev/null >/dev/null 2>&1 &
    exit 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# --- read-only commands ------------------------------------------------------
# Everything PyUI shows about WiFi comes from these, so it never has to know
# whether the device runs wpa_supplicant or NetworkManager, or where the saved
# networks live. Output goes to stdout; a missing value is an empty field.

WIFI_IFACE="wlan0"

wifi_uses_nm() {
    device_manages_own_wifi && command -v nmcli >/dev/null 2>&1
}

# nmcli -t escapes ":" in values as "\:".
nm_unescape() {
    sed 's/\\:/:/g; s/\\\\/\\/g'
}

wifi_ipv4() {
    _ip=""
    if command -v ip >/dev/null 2>&1; then
        _ip="$(ip -4 -o addr show dev "$WIFI_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)"
    fi
    if [ -z "$_ip" ] && command -v ifconfig >/dev/null 2>&1; then
        _ip="$(ifconfig "$WIFI_IFACE" 2>/dev/null | sed -n 's/.*inet \(addr:\)\{0,1\}\([0-9.]*\).*/\2/p' | head -n 1)"
    fi
    printf '%s' "$_ip"
}

wifi_saved_networks() {
    if wifi_uses_nm; then
        # NetworkManager names a profile made by "device wifi connect" after its SSID.
        nmcli -t -f TYPE,NAME connection show 2>/dev/null | sed -n 's/^802-11-wireless://p' | nm_unescape
    elif [ -n "$WPA_SUPPLICANT_FILE" ] && [ -f "$WPA_SUPPLICANT_FILE" ]; then
        sed -n 's/^[[:space:]]*ssid="\(.*\)"[[:space:]]*$/\1/p' "$WPA_SUPPLICANT_FILE"
    fi
}

# Sets _ssid and _freq for the network the interface is joined to, else empty.
# wpa_cli prints the SSID with non-printables escaped as \xHH; PyUI decodes.
wifi_link_info() {
    _ssid=""
    _freq=""
    if wifi_uses_nm; then
        _ssid="$(nmcli -t -f GENERAL.CONNECTION device show "$WIFI_IFACE" 2>/dev/null | sed -n 's/^GENERAL.CONNECTION://p' | nm_unescape | head -n 1)"
        [ "$_ssid" = "--" ] && _ssid=""
        if [ -n "$_ssid" ] && command -v iw >/dev/null 2>&1; then
            _freq="$(iw dev "$WIFI_IFACE" link 2>/dev/null | sed -n 's/.*freq: \([0-9]*\).*/\1/p' | head -n 1)"
        fi
    elif command -v wpa_cli >/dev/null 2>&1; then
        _st="$(wpa_cli -i "$WIFI_IFACE" status 2>/dev/null)"
        case "$_st" in
            *wpa_state=COMPLETED*)
                _ssid="$(printf '%s\n' "$_st" | sed -n 's/^ssid=//p' | head -n 1)"
                _freq="$(printf '%s\n' "$_st" | sed -n 's/^freq=//p' | head -n 1)"
                ;;
        esac
    fi
}

# RSSI in dBm, or nothing. /proc/net/wireless first: it is a plain read and
# every driver here but BaseOS's fills it. The RTL8723DS reports its level as
# 100+dBm, so a positive value is shifted back. Then wpa_cli signal_poll (the
# only source on BaseOS), then iw.
wifi_signal_dbm() {
    _sig=""
    if [ -r /proc/net/wireless ]; then
        _sig="$(awk -v i="$WIFI_IFACE:" '$1 == i { v = $4; sub(/\.$/, "", v); print int(v) }' /proc/net/wireless 2>/dev/null)"
        if [ -n "$_sig" ] && [ "$_sig" -gt 0 ] 2>/dev/null; then
            _sig=$((_sig - 100))
        fi
        [ "$_sig" = "0" ] && _sig=""
    fi
    if [ -z "$_sig" ] && command -v wpa_cli >/dev/null 2>&1; then
        _sig="$(wpa_cli -i "$WIFI_IFACE" signal_poll 2>/dev/null | sed -n 's/^RSSI=\(-\{0,1\}[0-9]\{1,\}\)$/\1/p' | head -n 1)"
        [ "$_sig" = "0" ] && _sig=""
    fi
    if [ -z "$_sig" ] && command -v iw >/dev/null 2>&1; then
        _sig="$(iw dev "$WIFI_IFACE" link 2>/dev/null | sed -n 's/.*signal: \(-\{0,1\}[0-9]\{1,\}\) dBm.*/\1/p' | head -n 1)"
    fi
    printf '%s' "$_sig"
}

# One line per network: ssid, signal dBm, MHz, secured, bssid. Hidden networks
# are dropped: there is nothing to show and nothing to join by name.
wifi_scan_networks() {
    if wifi_uses_nm; then
        # --rescan auto lets NetworkManager decide whether its cache is stale;
        # forcing a sweep every call stalls an association in progress.
        # Multiline output puts one field per line, so a BSSID full of colons
        # needs no field splitting. nmcli's SIGNAL is 0-100; 100 is taken as
        # -50 dBm and 0 as -100.
        nmcli -t -m multiline -f SSID,SIGNAL,FREQ,SECURITY,BSSID device wifi list --rescan auto 2>/dev/null \
        | sed 's/\\:/:/g; s/\\\\/\\/g' \
        | awk -F: '
            { key = $1; sub(/^[^:]*:/, "", $0); val = $0 }
            key == "SSID"     { ssid = val }
            key == "SIGNAL"   { q = val + 0; if (q < 0) q = 0; if (q > 100) q = 100; sig = int(q / 2) - 100 }
            key == "FREQ"     { freq = val + 0 }
            key == "SECURITY" { sec = (val == "") ? 0 : 1 }
            key == "BSSID"    { if (ssid != "") printf "%s\t%d\t%d\t%d\t%s\n", ssid, sig, freq, sec, val }
        '
        return 0
    fi
    command -v wpa_cli >/dev/null 2>&1 || return 0
    # FAIL-BUSY means wpa_supplicant is associating. Do not wait on it: its own
    # scans still fill scan_results, and asking again only takes the radio
    # off-channel and stalls the join.
    _r="$(wpa_cli -i "$WIFI_IFACE" scan 2>&1)"
    case "$_r" in
        *FAIL-BUSY*|*"Failed to connect"*) ;;
        *) sleep 2 ;;
    esac
    wpa_cli -i "$WIFI_IFACE" scan_results 2>/dev/null | awk -F'\t' '
        NR > 1 && NF >= 5 && $5 != "" {
            sec = ($4 ~ /WPA|WEP/) ? 1 : 0
            printf "%s\t%d\t%d\t%d\t%s\n", $5, $3, $2, sec, $1
        }'
}

wifi_status_report() {
    echo "radio=$(wifi_available_on_device && echo 1 || echo 0)"
    echo "setting=$(wifi_setting_wanted && echo 1 || echo 0)"
    echo "suspended=$([ -e "$WIFI_SUSPENDED" ] && echo 1 || echo 0)"
    echo "busy=$([ -d "$WIFI_LOCK" ] && echo 1 || echo 0)"
    _state="$(cat "$WIFI_STATE_FILE" 2>/dev/null)"
    echo "state=$_state"

    _ip=""
    _ssid=""
    _freq=""
    _sig=""
    _saved="$(wifi_saved_networks | grep -c .)"
    if ! wifi_available_on_device; then
        _link="no_radio"
    elif ! wifi_setting_wanted || [ -e "$WIFI_SUSPENDED" ]; then
        _link="off"
    else
        _ip="$(wifi_ipv4)"
        wifi_link_info
        if [ -n "$_ip" ]; then
            _link="connected"
            _sig="$(wifi_signal_dbm)"
        elif [ "$_saved" = "0" ]; then
            _link="no_network"
        elif [ "$_state" = "failed" ]; then
            _link="error"
        else
            _link="connecting"
        fi
    fi
    echo "link=$_link"
    echo "ssid=$_ssid"
    echo "freq=$_freq"
    echo "ip=$_ip"
    echo "signal=$_sig"
    echo "saved=$_saved"
}

if [ "$READ_ONLY" = 1 ]; then
    case "$CMD" in
        status) wifi_status_report ;;
        ip)     printf '%s\n' "$(wifi_ipv4)" ;;
        saved)  wifi_saved_networks ;;
        scan)   wifi_scan_networks ;;
    esac
    exit 0
fi
# --- end read-only commands --------------------------------------------------

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
dead_holder=""
locked=0
while :; do
    if mkdir "$WIFI_LOCK" 2>/dev/null; then
        locked=1
        break
    fi
    holder="$(cat "$WIFI_LOCK/pid" 2>/dev/null)"
    if [ -z "$holder" ]; then
        # The holder writes its pid just after mkdir; only an empty pid that stays empty is stale
        dead_holder=""
        empty_pid_ticks=$((empty_pid_ticks + 1))
        if [ "$empty_pid_ticks" -gt 10 ]; then
            log_message "wifi.sh: clearing a lock with no holder"
            rm -rf "$WIFI_LOCK"
            empty_pid_ticks=0
            continue
        fi
    elif wifi_sh_is_running "$holder"; then
        empty_pid_ticks=0
        dead_holder=""
    elif [ "$holder" = "$dead_holder" ]; then
        # Dead on two checks in a row. A holder that was only releasing is gone by the second
        # check, and one seen dead once may already be someone else's fresh lock.
        log_message "wifi.sh: clearing stale lock from $holder"
        rm -rf "$WIFI_LOCK"
        dead_holder=""
        continue
    else
        dead_holder="$holder"
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
