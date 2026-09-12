#!/bin/sh
# Standalone Miniloong WiFi diagnostic / bring-up tester.
#
# Run from a shell on the device (ADB/serial), NOT from PyUI, so a hang can never
# freeze the UI. EVERY step that can block is wrapped in `timeout`, so the script
# itself always returns and tells you which step stalled.
#
#   sh wifi-diag.sh                 # inventory + scan only (non-destructive)
#   sh wifi-diag.sh <SSID> <PSK>    # also try to connect + DHCP
#   sh wifi-diag.sh <SSID>          # open network (no PSK)
#
# Logs to console and /mnt/SDCARD/Saves/spruce/wifi-diag.log.

SSID="${1:-}"
PSK="${2:-}"
IFACE=wlan0
CONF=/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf
LOG=/mnt/SDCARD/Saves/spruce/wifi-diag.log
# Prefer spruce's bundled binaries, then the stock rootfs.
export PATH="/mnt/SDCARD/spruce/bin64:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

mkdir -p "${LOG%/*}" 2>/dev/null
say() { printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$*" | tee -a "$LOG"; }
# run <seconds> <label> <cmd...> : bounded, logged; reports TIMEOUT/rc.
run() {
    _t="$1"; _label="$2"; shift 2
    say ">> $_label: $*"
    _out="$(timeout "$_t" "$@" 2>&1)"; _rc=$?
    [ -n "$_out" ] && printf '%s\n' "$_out" | sed 's/^/     /' | tee -a "$LOG" >/dev/null
    if [ "$_rc" = 124 ]; then say "   !! TIMEOUT after ${_t}s (this step hangs) <<"; else say "   rc=$_rc"; fi
    return "$_rc"
}
have() { command -v "$1" >/dev/null 2>&1 && echo yes || echo NO; }

say "===== wifi-diag start ====="

say "-- binaries --"
for b in wpa_supplicant wpa_cli udhcpc dhcpcd iw ifconfig ip; do say "   $b: $(have $b) ($(command -v $b 2>/dev/null))"; done

say "-- driver / interface --"
run 5 "ip link" ip link show "$IFACE"
say "   /sys/class/net/$IFACE: $([ -d /sys/class/net/$IFACE ] && echo present || echo ABSENT)"
say "   operstate: $(cat /sys/class/net/$IFACE/operstate 2>/dev/null || echo n/a)"
say "   rkwifi power node: $(ls /sys/class/rkwifi 2>/dev/null | tr '\n' ' ')"
run 5 "lsmod wifi" sh -c "lsmod | grep -iE 'wifi|wlan|cfg80211|8189|8821|8188|rtl|aic|bcmdhd'"
run 5 "iw dev" iw dev
run 5 "wpa_supplicant running?" sh -c "pgrep -a wpa_supplicant || echo '(not running)'"
run 5 "dhcp client running?" sh -c "pgrep -a 'udhcpc|dhcpcd' || echo '(none)'"

if [ ! -d /sys/class/net/$IFACE ]; then
    say "!! $IFACE does not exist yet - trying power-on + module load"
    [ -w /sys/class/rkwifi/wifi_power ] && run 3 "power on" sh -c "echo 1 > /sys/class/rkwifi/wifi_power"
    run 10 "ifconfig up" ifconfig "$IFACE" up
    say "   after: /sys/class/net/$IFACE = $([ -d /sys/class/net/$IFACE ] && echo present || echo STILL ABSENT)"
fi

say "-- bring interface up --"
run 10 "ifconfig up" ifconfig "$IFACE" up

say "-- wpa_supplicant --"
if ! pgrep -x wpa_supplicant >/dev/null 2>&1; then
    if [ ! -f "$CONF" ]; then
        printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n' > "$CONF"
        say "   wrote minimal $CONF"
    fi
    run 15 "start wpa_supplicant -D nl80211" wpa_supplicant -B -D nl80211 -i "$IFACE" -c "$CONF"
    sleep 1
    run 5 "wpa_supplicant running?" sh -c "pgrep -a wpa_supplicant || echo '(FAILED to stay up - try -D wext)'"
else
    say "   wpa_supplicant already running"
fi

say "-- scan --"
run 8 "wpa_cli scan" wpa_cli -i "$IFACE" scan
sleep 3
run 8 "wpa_cli scan_results" wpa_cli -i "$IFACE" scan_results

if [ -n "$SSID" ]; then
    say "-- connect to '$SSID' --"
    NID="$(timeout 5 wpa_cli -i "$IFACE" add_network 2>/dev/null | tail -1)"
    say "   add_network -> id=$NID"
    if [ -n "$NID" ]; then
        run 5 "set ssid" wpa_cli -i "$IFACE" set_network "$NID" ssid "\"$SSID\""
        if [ -n "$PSK" ]; then run 5 "set psk" wpa_cli -i "$IFACE" set_network "$NID" psk "\"$PSK\"";
        else run 5 "open" wpa_cli -i "$IFACE" set_network "$NID" key_mgmt NONE; fi
        run 10 "enable_network" wpa_cli -i "$IFACE" enable_network "$NID"
        run 5 "save_config" wpa_cli -i "$IFACE" save_config
        sleep 4
        run 5 "status" wpa_cli -i "$IFACE" status
        say "-- DHCP --"
        run 30 "udhcpc" udhcpc -i "$IFACE" -n -t 5 -T 3
        run 5 "ip addr" ip -4 addr show "$IFACE"
    fi
fi

say "===== wifi-diag done (log: $LOG) ====="
