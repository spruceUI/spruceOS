#!/bin/sh
# USB WiFi dongle contract for devices that already have an onboard radio.
#
# Sourced by a platform device file (today: trimui_a133p.sh for the Brick, Brick
# Pro and Smart Pro). The platform cfg points at the modules and names the
# onboard driver; everything else is generic:
#
#   WIFI_USB_MODULES_DIR   directory holding <module>.ko for this kernel. Unset
#                          or empty means "no dongle support": every function
#                          below answers "no dongle" and the device's own WiFi
#                          path runs exactly as before.
#   WIFI_ONBOARD_MODULE    the module that owns the onboard wlan0 (xradio_wlan
#                          on the A133P). It is unloaded while a dongle is in
#                          use so the dongle's interface gets the wlan0 name -
#                          the shell and PyUI WiFi paths assume wlan0 throughout,
#                          and renaming the dongle beats teaching thirty call
#                          sites about a second interface.
#
# Model, borrowed from the RG28XX's bus-first USB radio contract
# (AnbernicXXCommon.sh): look at the USB bus, and only then touch a driver.
#   - a supported dongle enumerated -> its module replaces the onboard driver,
#     its interface becomes wlan0, and the ordinary enable_wifi flow continues
#     (supplicant, DHCP, network services) on top of it;
#   - no dongle -> the onboard radio, untouched;
#   - a dongle whose module refuses to load is remembered for the session
#     (WIFI_USB_DONGLE_FAILED) and the onboard radio is used instead;
#   - usb_wifi_watchdog.sh polls the bus and runs usb_wifi_hotplug_event on
#     arrival/removal, so plugging the dongle in after boot, or pulling it,
#     swaps radios without a reboot as long as WiFi is switched on.
#
# Nothing here writes the port role. On the sunxi OTG manager the dongle can
# only be seen once the port is host; whether the manager selects host on its
# own when nothing supplies VBUS (as the RG28XX's does) or needs the vendor's
# usb_host.sh is a per-device fact - see docs/research/usb-wifi-modules/.
# usb_wifi_port_host_mode exists for the platforms that need the explicit
# switch and is only used when the cfg sets WIFI_USB_FORCE_HOST_MODE=1.

WIFI_USB_MODULES_DIR="${WIFI_USB_MODULES_DIR:-}"
WIFI_ONBOARD_MODULE="${WIFI_ONBOARD_MODULE:-}"
WIFI_USB_SYS="${WIFI_USB_SYS:-/sys/bus/usb/devices}"
WIFI_USB_FORCE_HOST_MODE="${WIFI_USB_FORCE_HOST_MODE:-0}"
# "id module" while a dongle's driver is the active radio; absent otherwise.
WIFI_USB_DONGLE_STATE="${WIFI_USB_DONGLE_STATE:-/tmp/wifi_usb_dongle}"
# One id per line: dongles whose module refused to load this session.
WIFI_USB_DONGLE_FAILED="${WIFI_USB_DONGLE_FAILED:-/tmp/wifi_usb_dongle_failed}"
# How long to wait for the driver's probe to create the interface after insmod.
WIFI_USB_IFACE_WAIT="${WIFI_USB_IFACE_WAIT:-8}"

# USB ids per module, straight from the modules' own device tables
# (modinfo -F alias <module>.ko, lower-cased vvvv:pppp). Regenerate when a
# module is rebuilt from a different driver version; keep the two in sync with
# tools/a133-usb-wifi/README.md in the wrapper.
#   8188eu: RTL8188EU/EUS - TL-WN725N v2/v3 and the generic 8188EU dongles
#   8812au: RTL8811AU/8812AU/8821AU - TP-Link Archer T2U Nano (2357:011e), T2U,
#           T2U Plus, T4U and the rest of the aircrack-ng rtl8812au table
WIFI_USB_IDS_8188EU="0bda:8179 0bda:0179 0bda:f179 2357:010c 2357:0111 07b8:8179 2001:330f 2001:3310 2001:3311 2001:331b 0b05:18f0 7392:b811 0df6:0076 056e:4008 2c4e:0102"
WIFI_USB_IDS_8812AU="2357:011e 2357:011f 2357:0120 2357:0101 2357:0103 2357:010d 2357:010e 2357:010f 2357:0122 0bda:0811 0bda:0820 0bda:0821 0bda:0823 0bda:8812 0bda:881a 0bda:881b 0bda:881c 0bda:8822 0bda:a811 0409:0408 0411:0242 0411:025d 0411:029b 04bb:0952 04bb:0953 050d:1106 050d:1109 056e:4007 056e:400e 056e:400f 056e:4010 0586:3426 0789:016e 07b8:8812 0846:9051 0846:9052 0b05:17d2 0df6:0074 0e66:0022 0e66:0023 1058:0632 13b1:003f 148f:9097 1740:0100 2001:330e 2001:3313 2001:3314 2001:3315 2001:3316 2001:3318 2019:ab30 2019:ab32 20f4:805b 2604:0012 3823:6249 7392:a811 7392:a812 7392:a813 7392:a822 7392:b611"
# Exported so PyUI (launched from a shell that sourced this) sees the same list.
if [ -n "$WIFI_USB_MODULES_DIR" ]; then
    export WIFI_USB_IDS="$WIFI_USB_IDS_8188EU $WIFI_USB_IDS_8812AU"
fi

# Which module drives this id; prints nothing for an unknown id.
usb_wifi_module_for_id() {
    case " $WIFI_USB_IDS_8188EU " in *" $1 "*) echo 8188eu; return 0 ;; esac
    case " $WIFI_USB_IDS_8812AU " in *" $1 "*) echo 8812au; return 0 ;; esac
    return 1
}

usb_wifi_module_loaded() {
    grep -q "^$1 " /proc/modules 2>/dev/null
}

# The sysfs device directory of the first supported dongle on the bus.
usb_wifi_dongle_sysdir() {
    [ -n "$WIFI_USB_MODULES_DIR" ] || return 1
    for _ud in "$WIFI_USB_SYS"/*; do
        [ -r "$_ud/idVendor" ] || continue
        _uid="$(cat "$_ud/idVendor" 2>/dev/null):$(cat "$_ud/idProduct" 2>/dev/null)"
        if usb_wifi_module_for_id "$_uid" >/dev/null; then
            echo "$_ud"
            return 0
        fi
    done
    return 1
}

# Is a supported dongle enumerated? Prints its vvvv:pppp. Instant sysfs read.
usb_wifi_dongle_present() {
    _dd="$(usb_wifi_dongle_sysdir)" || return 1
    echo "$(cat "$_dd/idVendor" 2>/dev/null):$(cat "$_dd/idProduct" 2>/dev/null)"
}

# The network interface the dongle's driver created, whatever it is called:
# sysfs hangs it under the device's interface directory (<bus>-<port>:1.0/net/).
usb_wifi_dongle_iface() {
    _dd="$(usb_wifi_dongle_sysdir)" || return 1
    for _n in "$_dd"/*:*/net/*; do
        [ -e "$_n" ] || continue
        basename "$_n"
        return 0
    done
    return 1
}

# Is the dongle path the active radio: state recorded, module loaded, dongle
# still on the bus.
usb_wifi_dongle_active() {
    [ -r "$WIFI_USB_DONGLE_STATE" ] || return 1
    read -r _sid _smod < "$WIFI_USB_DONGLE_STATE" 2>/dev/null || return 1
    usb_wifi_module_loaded "$_smod" || return 1
    [ "$(usb_wifi_dongle_present 2>/dev/null)" = "$_sid" ]
}

usb_wifi_dongle_failed_before() {
    [ -r "$WIFI_USB_DONGLE_FAILED" ] && grep -qx "$1" "$WIFI_USB_DONGLE_FAILED" 2>/dev/null
}

# Stop the clients that hold the old wlan0 so enable_wifi starts fresh ones on
# the new one. The pieces of disable_wifi without its flags and log line.
usb_wifi_stop_clients() {
    killall -9 wpa_supplicant 2>/dev/null
    if command -v device_stop_dhcp_client >/dev/null 2>&1; then
        device_stop_dhcp_client
    else
        killall -9 udhcpc 2>/dev/null
    fi
}

_usb_wifi_wait_iface() { # seconds -> prints the dongle iface name
    _left="${1:-8}"
    while [ "$_left" -gt 0 ]; do
        _if="$(usb_wifi_dongle_iface 2>/dev/null)" && { echo "$_if"; return 0; }
        sleep 1
        _left=$((_left - 1))
    done
    usb_wifi_dongle_iface 2>/dev/null
}

# Make the dongle the radio. 0 = wlan0 is the dongle; 1 = no dongle, or it
# cannot be used (already logged) - the caller falls back to the onboard radio.
# Idempotent and cheap when the dongle is already active (every game exit
# re-runs enable_wifi).
usb_wifi_bring_up() {
    [ -n "$WIFI_USB_MODULES_DIR" ] || return 1
    _id="$(usb_wifi_dongle_present)" || return 1
    _mod="$(usb_wifi_module_for_id "$_id")" || return 1

    if usb_wifi_dongle_active && [ -d /sys/class/net/wlan0 ]; then
        return 0
    fi
    if usb_wifi_dongle_failed_before "$_id"; then
        return 1
    fi
    if [ ! -f "$WIFI_USB_MODULES_DIR/$_mod.ko" ]; then
        log_message "USB WiFi: $_id needs $_mod.ko but $WIFI_USB_MODULES_DIR has none - onboard radio stays"
        echo "$_id" >> "$WIFI_USB_DONGLE_FAILED" 2>/dev/null
        return 1
    fi

    # Free the wlan0 name: the onboard driver goes, and so do the clients that
    # were bound to its interface.
    usb_wifi_stop_clients
    if [ -n "$WIFI_ONBOARD_MODULE" ] && usb_wifi_module_loaded "$WIFI_ONBOARD_MODULE"; then
        rmmod "$WIFI_ONBOARD_MODULE" 2>/dev/null
        log_message "USB WiFi: $_id on the bus - onboard $WIFI_ONBOARD_MODULE unloaded in its favour"
    fi

    if ! usb_wifi_module_loaded "$_mod"; then
        if ! insmod "$WIFI_USB_MODULES_DIR/$_mod.ko" 2>/tmp/wifi_usb_insmod_err; then
            log_message "USB WiFi: insmod $_mod.ko failed: $(head -1 /tmp/wifi_usb_insmod_err 2>/dev/null); kernel: $(dmesg 2>/dev/null | grep -i "$_mod" | tail -1) - onboard radio stays"
            echo "$_id" >> "$WIFI_USB_DONGLE_FAILED" 2>/dev/null
            rm -f "$WIFI_USB_DONGLE_STATE" 2>/dev/null
            return 1
        fi
        log_message "USB WiFi: $_mod loaded for $_id"
    fi

    _if="$(_usb_wifi_wait_iface "$WIFI_USB_IFACE_WAIT")"
    if [ -z "$_if" ]; then
        log_message "USB WiFi: $_mod loaded but no interface for $_id after ${WIFI_USB_IFACE_WAIT}s - onboard radio stays"
        rmmod "$_mod" 2>/dev/null
        echo "$_id" >> "$WIFI_USB_DONGLE_FAILED" 2>/dev/null
        rm -f "$WIFI_USB_DONGLE_STATE" 2>/dev/null
        return 1
    fi
    if [ "$_if" != wlan0 ]; then
        # The onboard driver still owned wlan0 when the dongle probed (a dongle
        # loaded before this contract ran, or a stale wlan0). Rename now that
        # the name is free; if it is not, give up rather than run two radios.
        if [ -d /sys/class/net/wlan0 ]; then
            log_message "USB WiFi: dongle is $_if but wlan0 still exists - onboard radio stays"
            return 1
        fi
        ip link set "$_if" down 2>/dev/null
        if ! ip link set "$_if" name wlan0 2>/dev/null; then
            log_message "USB WiFi: could not rename $_if to wlan0 - onboard radio stays"
            return 1
        fi
        log_message "USB WiFi: $_if renamed to wlan0"
    fi
    echo "$_id $_mod" > "$WIFI_USB_DONGLE_STATE" 2>/dev/null
    return 0
}

# Unload whichever dongle module is loaded and forget the dongle state. Safe
# to call when nothing is loaded.
usb_wifi_tear_down() {
    for _m in 8188eu 8812au; do
        if usb_wifi_module_loaded "$_m"; then
            rmmod "$_m" 2>/dev/null
            log_message "USB WiFi: $_m unloaded"
        fi
    done
    rm -f "$WIFI_USB_DONGLE_STATE" 2>/dev/null
}

# Put the onboard driver back if it is not loaded and wait for its wlan0.
usb_wifi_onboard_restore() {
    [ -n "$WIFI_ONBOARD_MODULE" ] || return 0
    if ! usb_wifi_module_loaded "$WIFI_ONBOARD_MODULE"; then
        modprobe "$WIFI_ONBOARD_MODULE" 2>/dev/null
        log_message "USB WiFi: onboard $WIFI_ONBOARD_MODULE reloaded"
    fi
    _left=5
    while [ "$_left" -gt 0 ]; do
        [ -d /sys/class/net/wlan0 ] && return 0
        sleep 1
        _left=$((_left - 1))
    done
    [ -d /sys/class/net/wlan0 ]
}

# Called by usb_wifi_watchdog.sh: "arrived <id>" / "removed <id>". Only swaps
# radios when the user has WiFi on; with WiFi off it just keeps the driver
# state consistent, and the next enable does the rest.
usb_wifi_hotplug_event() {
    _ev="$1"; _eid="$2"
    _want=0
    [ -n "$SYSTEM_JSON" ] && [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON" 2>/dev/null)" = 1 ] && _want=1
    case "$_ev" in
        arrived)
            log_message "USB WiFi: dongle $_eid arrived ($(usb_wifi_module_for_id "$_eid" 2>/dev/null || echo unknown)); WiFi $([ "$_want" = 1 ] && echo on || echo off)"
            [ "$_want" = 1 ] || return 0
            usb_wifi_bring_up >/dev/null 2>&1 || return 0
            enable_wifi
            ;;
        removed)
            log_message "USB WiFi: dongle $_eid removed"
            usb_wifi_tear_down
            usb_wifi_stop_clients
            [ "$_want" = 1 ] || return 0
            enable_wifi
            ;;
    esac
}

# --- port role (sunxi OTG manager) ------------------------------------------
# otg_role is the one node that is safe to read; the sibling usb_host /
# usb_device / usb_null files switch the role when READ and are never touched.
usb_wifi_port_role() {
    for _r in /sys/devices/platform/soc/usbc0/otg_role /sys/devices/platform/usbc0/otg_role \
              /sys/bus/platform/devices/usbc0/otg_role; do
        [ -r "$_r" ] && { cat "$_r" 2>/dev/null; return 0; }
    done
    return 1
}

# Ask the manager for host mode. Refuses while the PMIC sees VBUS (a charger or
# PC on the port: switching would drop that link and try to source 5 V into
# it). Used only when the cfg sets WIFI_USB_FORCE_HOST_MODE=1.
usb_wifi_port_host_mode() {
    [ "$WIFI_USB_FORCE_HOST_MODE" = 1 ] || return 1
    [ "$(usb_wifi_port_role)" = usb_host ] && return 0
    if [ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" = 1 ]; then
        return 1
    fi
    for _r in /sys/devices/platform/soc/usbc0/otg_role /sys/devices/platform/usbc0/otg_role \
              /sys/bus/platform/devices/usbc0/otg_role; do
        [ -w "$_r" ] || continue
        echo usb_host > "$_r" 2>/dev/null
        log_message "USB WiFi: port switched to host mode"
        return 0
    done
    return 1
}
