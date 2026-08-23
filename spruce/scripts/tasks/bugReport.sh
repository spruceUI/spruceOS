#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

output7z=/mnt/SDCARD/bug_report.7z
device_state=/mnt/SDCARD/Saves/spruce/device_state.log

if [ -f $output7z ] ; then
    rm $output7z
fi

# Hardware state that the logs don't record. Landing it in Saves/spruce as a
# .log means the include patterns below already pick it up.
dump_node() {
    if [ -e "$1" ]; then
        printf '%s = %s\n' "$1" "$(cat "$1" 2>/dev/null || echo '<unreadable>')"
    else
        printf '%s = <missing>\n' "$1"
    fi
}

# PRIVACY. This whole file is packaged into a 7z that users hand to strangers,
# so the redactors are defined here rather than inside one section: every raw
# dump in this script is a place a MAC or an address can escape, and the wifi
# section is only the most obvious one. Pipe anything you do not control.
#
# redact_mac deliberately leaves 00:00:00:00:00:00 legible and tags it: a zeroed
# MAC means the driver bound and firmware never loaded, and that fault signature
# is indistinguishable from a healthy interface once redacted like any other.
# Written without sed interval expressions - busybox 1.27.2 on the Brick does
# not reliably support \{n\}.
_HEX2='[0-9a-fA-F][0-9a-fA-F]'
redact_mac() {
    sed -e 's/00:00:00:00:00:00/@ZEROMAC@/g' \
        -e "s/$_HEX2:$_HEX2:$_HEX2:$_HEX2:$_HEX2:$_HEX2/<mac-redacted>/g" \
        -e 's/@ZEROMAC@/00:00:00:00:00:00 <ALL-ZERO>/g' 2>/dev/null
}

# A global IPv6 address, and the /64 prefix inside it, identify the user's
# connection at least as precisely as a MAC and diagnose nothing on these
# devices. Link-local (fe80::) and loopback (::1) are neither routable nor
# identifying, so they survive - they are also the only two that ever say
# anything useful here.
# Line-wise, and the address token must contain TWO colons - "addr:" is three
# hex characters followed by a colon, so a looser pattern eats the label and
# prints "inet6 <redacted>r:". Learned from a real report.
redact_ip6() {
    sed -e '/inet6/{' -e '/fe80:/b' -e '/::1/b' \
        -e 's/[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F:]*/<ipv6-redacted>/' -e '}' 2>/dev/null
}

{
    echo "==== device ===="
    echo "date          : $(date)"
    echo "PLATFORM      : $PLATFORM"
    echo "DEVICE        : $DEVICE"
    if command -v get_miyoo_mini_variant >/dev/null 2>&1; then
        echo "mini variant  : $(get_miyoo_mini_variant 2>/dev/null)"
    fi
    echo "spruce version: $(cat /mnt/SDCARD/spruce/spruce 2>/dev/null)"

    echo
    echo "==== display / backlight nodes ===="
    echo "/sys/class/pwm/pwmchip0 :"
    ls -1 /sys/class/pwm/pwmchip0 2>/dev/null || echo "  <missing>"
    dump_node /sys/class/pwm/pwmchip0/pwm0/duty_cycle
    dump_node /sys/class/pwm/pwmchip0/pwm0/period
    dump_node /sys/class/pwm/pwmchip0/pwm0/enable
    dump_node /sys/devices/soc0/soc/1f003400.pwm/pwm/pwmchip0/pwm0/duty_cycle
    echo "/proc/mi_modules :"
    if [ -d /proc/mi_modules ]; then
        # Listing one level down as well: the display settings need the exact
        # node name inside mi_disp, and the top level listing does not show it.
        for entry in /proc/mi_modules/*; do
            if [ -d "$entry" ]; then
                echo "  $entry/"
                for child in "$entry"/*; do
                    [ -e "$child" ] && echo "      $(basename "$child")"
                done
            else
                echo "  $entry"
            fi
        done
    else
        echo "  <missing>"
    fi

    echo
    echo "==== MI libraries (so we know the real names and where they live) ===="
    for d in /config/lib /customer/lib /usr/lib; do
        echo "  $d:"
        ls -1 "$d" 2>/dev/null | grep -i "^libmi" | sed 's/^/      /' || echo "      <none>"
    done

    echo
    echo "==== /dev mi nodes ===="
    ls -l /dev/mi_* 2>/dev/null || echo "  <none>"

    echo
    echo "==== probe: does opening the disp device create its proc node? ===="
    echo "before:"
    ls -1 /proc/mi_modules/mi_disp 2>/dev/null | sed 's/^/  /'
    if [ -e /dev/mi_disp ]; then
        # Just opening it, no ioctls. If the instance node appears afterwards then
        # mi_disp0 is missing only because nothing had the display open.
        ( exec 3<>/dev/mi_disp; sleep 1; exec 3>&- ) 2>/dev/null &
        probe_pid=$!
        sleep 0.3
        echo "during open:"
        ls -1 /proc/mi_modules/mi_disp 2>/dev/null | sed 's/^/  /'
        wait $probe_pid 2>/dev/null
        echo "after close:"
        ls -1 /proc/mi_modules/mi_disp 2>/dev/null | sed 's/^/  /'
    else
        echo "  /dev/mi_disp does not exist, cannot probe"
    fi

    echo
    echo "==== csc probe: what does the driver say about each command? ===="
    # colortemp is proven to reach the panel (a hard rgb cast showed up on screen)
    # but csc produces no output and no visible effect. Feed the node a few things
    # and read dmesg after each -- these drivers usually print usage on a command
    # they do not recognise, which tells us the real argument list.
    # Hold the device open ourselves for the duration. PyUI is stopped while a
    # task runs, so its handle is gone and the node with it -- we cannot rely on
    # anything else keeping it alive here.
    if [ -e /dev/mi_disp ]; then
        exec 3<>/dev/mi_disp
        if [ -e /proc/mi_modules/mi_disp/mi_disp0 ]; then
            for cmd in "help" "csc" "csc 0" "csc 0 3 50 50 50 0 0 0" "colortemp 0 0 0 0 128 128 128"; do
                dmesg -c >/dev/null 2>&1
                echo "  --- wrote: [$cmd]"
                echo "$cmd" > /proc/mi_modules/mi_disp/mi_disp0 2>&1
                sleep 0.2
                dmesg 2>/dev/null | tail -12 | sed 's/^/      /'
            done
            echo
            echo "  --- CscMatrix sweep: saturation forced to 0, 3s per matrix ---"
            echo "  --- watch the screen and note which step turns it grey ---"
            for m in 0 1 2 3 4 5 6 7; do
                echo "  step $m: csc 0 $m 50 50 50 0 0 0"
                echo "csc 0 $m 50 50 50 0 0 0" > /proc/mi_modules/mi_disp/mi_disp0 2>&1
                sleep 3
            done
            # put it back to something neutral before we let go
            echo "csc 0 0 50 50 50 50 0 0" > /proc/mi_modules/mi_disp/mi_disp0 2>&1
        else
            echo "  node did not appear after opening /dev/mi_disp"
        fi
        exec 3>&-
    else
        echo "  /dev/mi_disp does not exist"
    fi

    echo
    echo "==== what the display proc nodes report when read ===="
    echo "--- /proc/mi_modules/fb/mi_fb0 ---"
    head -c 4000 /proc/mi_modules/fb/mi_fb0 2>/dev/null || echo "  <unreadable>"
    echo
    echo "--- /proc/mi_modules/mi_disp/mi_disp0 (opening the device ourselves) ---"
    if [ -e /dev/mi_disp ]; then
        exec 4<>/dev/mi_disp
        head -c 4000 /proc/mi_modules/mi_disp/mi_disp0 2>/dev/null || echo "  <unreadable>"
        exec 4>&-
    else
        echo "  /dev/mi_disp does not exist"
    fi
    echo
    echo "--- /proc/mi_modules/mi_panel/* ---"
    for n in /proc/mi_modules/mi_panel/*; do
        case "$n" in *debug_*|*module_version*) continue ;; esac
        echo "  == $n"
        head -c 2000 "$n" 2>/dev/null
    done
    echo
    echo "--- /proc/mi_modules/common/pq_info ---"
    head -c 2000 /proc/mi_modules/common/pq_info 2>/dev/null || echo "  <unreadable>"

    echo
    echo "==== kernel log tail (may show rejected display commands) ===="
    # Redacted like every other dump: the radio driver prints both the adapter
    # MAC and the AP's address into the ring buffer during association, and
    # this generic tail picks them up whether or not it is a wifi report.
    _ktail=$(dmesg 2>/dev/null | tail -40)
    if [ -n "$_ktail" ]; then echo "$_ktail" | redact_mac; else echo "  <unavailable>"; fi

    echo
    echo "==== config files the display settings write to ===="
    dump_node /appconfigs/system.json
    dump_node /mnt/SDCARD/Saves/mini-flip-system.json

    echo
    echo "==== processes that apply those settings ===="
    ps 2>/dev/null | grep -iE "keymon|audioserver|MainUI|main$" | grep -v grep || echo "  none running"

    # WiFi. spruce itself loads no driver and creates no interface - it assumes
    # wlan0 exists and starts wpa_supplicant on it - so when a device finds no
    # networks the cause is almost always below us: no driver bound, missing
    # firmware, an interface under another name, a radio that never enumerated
    # on its bus, or an rfkill block. This section is meant to tell those apart
    # from a device with no SSH.
    #
    # PRIVACY CONTRACT - this file is packaged into a 7z that users hand to
    # strangers in a Discord thread. NOTHING here may print:
    #   - wpa_supplicant.conf contents (plaintext PSKs)
    #   - any SSID, ours or a neighbour's (home SSIDs carry surnames and unit
    #     numbers; scan results carry every network in range)
    #   - any MAC address (the device's own identifies the unit across reports;
    #     a BSSID geolocates the user through public wardriving databases)
    # Counts, states and IDs only. redact_mac below is the backstop for command
    # output we do not control - always pipe through it rather than trusting a
    # tool not to print a MAC.

    echo
    echo "==== wifi: interfaces ===="
    echo "BASEOS_TARGET : $(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null || echo '<not baseos>')"
    echo "/sys/class/net:"
    ls -1 /sys/class/net 2>/dev/null | sed 's/^/  /' || echo "  <missing>"
    for n in /sys/class/net/*/; do
        [ -d "$n" ] || continue
        i=$(basename "$n")
        case "$i" in lo) continue ;; esac
        echo "  $i: operstate=$(cat "$n/operstate" 2>/dev/null) address=$(cat "$n/address" 2>/dev/null | redact_mac)"
        [ -e "$n/wireless" ] && echo "      (wireless)"
        [ -L "$n/phy80211" ] && echo "      (has phy80211 - cfg80211 registered)"
        [ -e "$n/device/uevent" ] && sed 's/^/      /' "$n/device/uevent" 2>/dev/null | redact_mac
    done

    echo
    echo "==== wifi: driver ===="
    echo "loaded modules:"
    lsmod 2>/dev/null | sed 's/^/  /' || echo "  <lsmod unavailable>"
    # Discover the radio driver rather than naming it: the XX line alone spans
    # 8821cs (SDIO) and 8188eu (USB), and hardcoding either reports a fault on
    # the other.
    wifi_drv=$(lsmod 2>/dev/null | awk 'NR>1{print $1}' \
               | grep -iE '^(8821[a-z]*|8188[a-z]*|8723[a-z]*|aic[0-9a-z]*|rtl[0-9a-z_]*)$' | head -1)
    echo "detected wifi module     : ${wifi_drv:-<none loaded>}"
    if [ -n "$wifi_drv" ]; then
        echo "  initstate : $(cat "/sys/module/$wifi_drv/initstate" 2>/dev/null)"
        echo "  refcount  : $(awk -v m="$wifi_drv" '$1==m{print $3}' /proc/modules 2>/dev/null)"
        # vermagic vs the running kernel. A module built for another kernel
        # fails to insmod with nothing but "Invalid module format" in dmesg,
        # and spruce ships 8188eu.ko itself for the RG28XX - so this is our
        # file to get wrong, not the OS image's.
        #
        # Read out of the .ko directly rather than with modinfo. BusyBox
        # modinfo insists on /lib/modules/$(uname -r)/modules.dep before it
        # will look at anything, BaseOS ships no such file, and it then FAILS
        # WITH EXIT 0 - so the field silently came back empty on the one
        # device family this check exists for. grep -a reads the string out of
        # the module image and needs nothing but the file.
        for k in /lib/modules/"$wifi_drv".ko /lib/modules/*/"$wifi_drv".ko \
                 /mnt/SDCARD/spruce/h700/rg28xx/"$wifi_drv".ko; do
            [ -f "$k" ] || continue
            echo "  module file : $k"
            _vm=$(grep -ao 'vermagic=[!-~ ]*' "$k" 2>/dev/null | head -1 | cut -d= -f2-)
            [ -n "$_vm" ] || _vm=$(modinfo -F vermagic "$k" 2>/dev/null)
            echo "  vermagic    : ${_vm:-<unreadable>}"
            # Spelled out rather than left to the reader: this is the whole
            # point of the field, and "Invalid module format" in dmesg is the
            # only other clue the device gives.
            case "$_vm" in
                "$(uname -r 2>/dev/null)"*) echo "  vermagic vs kernel : match" ;;
                "") ;;
                *) echo "  vermagic vs kernel : MISMATCH - this module cannot load on $(uname -r 2>/dev/null)" ;;
            esac
            break
        done
        echo "  running kernel : $(uname -r 2>/dev/null)"
        # Live module parameters. rtw_power_mgnt is documented upstream as the
        # cause of intermittent latency while the association stays healthy -
        # reading its actual value beats assuming the default.
        if [ -d "/sys/module/$wifi_drv/parameters" ]; then
            echo "  parameters of interest:"
            for prm in rtw_power_mgnt rtw_ips_mode rtw_lps_level rtw_country_code \
                       rtw_channel_plan rtw_wifi_spec rtw_antdiv_cfg; do
                p="/sys/module/$wifi_drv/parameters/$prm"
                [ -r "$p" ] || continue
                # Unset country_code reads back as raw bytes on this hardware,
                # which makes the whole report register as binary and stops grep
                # searching it - which is the first thing anyone tries.
                echo "    $prm = $(tr -d '\000-\010\013\014\016-\037\177-\377' < "$p" 2>/dev/null | head -1)"
            done
        fi
    fi
    echo "wifi firmware blobs present:"
    find /lib/firmware /vendor/firmware /etc/firmware -iname '*8188*' -o -iname '*8821*' \
         -o -iname '*8723*' -o -iname '*aic*' -o -iname '*rtl*' -o -iname '*wifi*' 2>/dev/null \
         | head -30 | sed 's/^/  /' || true
    echo "rfkill:"
    # Type matters more than the listing: on sunxi the wlan rfkill IS the power
    # control, so bluetooth having a switch while wlan has none is the mechanism
    # behind "the radio was never switched on", not a cosmetic difference.
    rfkill list 2>/dev/null | sed 's/^/  /' || echo "  <rfkill unavailable>"
    _rk_w=""; _rk_b=""; _rk_b_on=""
    for r in /sys/class/rfkill/rfkill*; do
        [ -d "$r" ] || continue
        _t=$(cat "$r/type" 2>/dev/null); _s=$(cat "$r/soft" 2>/dev/null)
        echo "  ${r##*/}: type=$_t soft=$_s hard=$(cat "$r/hard" 2>/dev/null)"
        [ "$_t" = "wlan" ] && _rk_w=yes
        [ "$_t" = "bluetooth" ] && { _rk_b=yes; [ "$_s" = "0" ] && _rk_b_on=yes; }
    done
    [ -n "$_rk_w" ] || echo "  NOTE: no wlan rfkill switch registered"

    echo
    echo "==== wifi: bus (sdio / mmc / sunxi) ===="
    # Where "the driver loaded but nothing appeared" is settled. A loaded driver
    # with an empty SDIO bus means the chip never answered - no userspace reload
    # changes that. Empty everywhere is NORMAL on USB and non-sunxi radios
    # (RG28XX is USB 8188eu, RK3566 and SigmaStar are not SDIO), so read this
    # together with the detected module above rather than on its own.
    echo "mmc hosts (controller name is the stable identity, not the index):"
    _mmc=""
    for h in /sys/class/mmc_host/mmc*; do
        [ -d "$h" ] || continue
        _mmc=yes
        _hn=${h##*/}
        _ctl=$(readlink -f "$h/device" 2>/dev/null | sed 's|.*/||')
        _bound=""
        for d in /sys/bus/mmc/devices/${_hn}:*; do [ -e "$d" ] && _bound="${d##*/}"; done
        echo "  $_hn: controller=${_ctl:-?} bound=${_bound:-<none>}"
    done
    [ -n "$_mmc" ] || echo "  <no mmc hosts>"
    echo "sdio devices (the radio appears here when it enumerates):"
    _sdio=""
    for d in /sys/bus/sdio/devices/*; do
        [ -e "$d" ] || continue
        _sdio=yes
        echo "  ${d##*/}: vendor=$(cat "$d/vendor" 2>/dev/null) device=$(cat "$d/device" 2>/dev/null) class=$(cat "$d/class" 2>/dev/null)"
        # 'auto' lets the card sleep, which reads as intermittent packet loss
        # while the association itself stays up.
        [ -r "$d/power/control" ] && echo "      power/control=$(cat "$d/power/control" 2>/dev/null)"
    done
    [ -n "$_sdio" ] || echo "  none enumerated"
    if [ -n "$wifi_drv" ] && [ -z "$_sdio" ] && [ -d /sys/bus/sdio ]; then
        echo "  NOTE: a wifi module is loaded and no SDIO device enumerated."
        echo "        On an SDIO radio that means the chip never answered."
        echo "        On a USB radio (8188eu) this is the expected state."
    fi
    echo "sunxi wlan platform node (owns the rail, the 32k clock and the rescan):"
    _sunxi=""
    for w in /sys/bus/platform/devices/*wlan* /sys/devices/platform/*wlan*; do
        [ -d "$w" ] || continue
        _sunxi=yes
        echo "  ${w##*/}: driver=$(readlink "$w/driver" 2>/dev/null | sed 's|.*/||' || echo '<UNBOUND>')"
        for a in "$w"/*; do
            [ -f "$a" ] || continue
            case "${a##*/}" in uevent|driver_override|modalias) continue ;; esac
            echo "      ${a##*/} = $(cat "$a" 2>/dev/null | head -1)"
        done
        break
    done
    [ -n "$_sunxi" ] || echo "  none (normal off sunxi)"
    [ -r /proc/driver/wifi-pm/power ] && echo "  wifi-pm power = $(cat /proc/driver/wifi-pm/power 2>/dev/null)"

    echo
    echo "==== wifi: radio state ===="
    # Built on wpa_cli, NOT iw. iw and iwconfig are absent on BaseOS, the Miyoo
    # Flip and both Minis - more than half the fleet - so the old iw-based
    # version of this section printed "<not installed>" and captured no
    # association state at all on exactly the devices we get reports from.
    # wpa_cli and udhcpc are the only wireless tools present everywhere.
    _if=wlan0
    [ -d /sys/class/net/wlan0 ] || _if=$(ls -d /sys/class/net/wlan* 2>/dev/null | head -1 | sed 's|.*/||')
    echo "interface : ${_if:-<none>}"
    if command -v wpa_cli >/dev/null 2>&1 && [ -n "$_if" ] \
       && ps 2>/dev/null | grep -q '[w]pa_supplicant'; then
        # ssid and bssid are dropped outright - see the privacy contract above.
        # Everything that actually diagnoses an association survives.
        # Anchored on purpose. An unanchored 'psk' also drops
        # key_mgmt=WPA-PSK, which carries no secret and is how you tell WPA2
        # from WPA3-SAE - a real source of association failures on these
        # drivers. Anything holding actual key material is a psk=/passphrase=
        # line, which this still catches.
        #
        # uuid is dropped too: wpa_supplicant derives it from the interface
        # MAC, so it is a stable per-device identifier that survives redacting
        # the MAC itself and links every report a unit ever files.
        wpa_cli -i "$_if" status 2>/dev/null \
            | grep -viE '^(ssid|bssid|psk|passphrase|password|uuid)=' \
            | redact_mac | sed 's/^/  /'
        wpa_cli -i "$_if" signal_poll 2>/dev/null | sed 's/^/  /'
        # Band, and whether this SSID is dual-band. A mixed-band AP advertises
        # one name on both; wpa_supplicant scores toward the 5GHz BSS, whose
        # association on XX hardware was measured at ~200s (61c97b9f0) - longer
        # than the DHCP window. Counts only, never the name.
        _freq=$(wpa_cli -i "$_if" status 2>/dev/null | sed -n 's/^freq=//p' | head -1)
        if [ -n "$_freq" ]; then
            _band=2.4GHz; [ "$_freq" -gt 4000 ] 2>/dev/null && _band=5GHz
            echo "  band : $_freq MHz ($_band)"
            _ssid=$(wpa_cli -i "$_if" status 2>/dev/null | sed -n 's/^ssid=//p' | head -1)
            if [ -n "$_ssid" ]; then
                _n24=0; _n5=0
                # scan_results reads the LAST scan; it starts none.
                while IFS= read -r _line; do
                    case "$_line" in bssid*|"") continue ;; esac
                    _lf=$(echo "$_line" | awk '{print $2}')
                    [ "$(echo "$_line" | cut -f5-)" = "$_ssid" ] || continue
                    if [ "$_lf" -gt 4000 ] 2>/dev/null; then _n5=$((_n5+1)); else _n24=$((_n24+1)); fi
                done <<SCANEOF
$(wpa_cli -i "$_if" scan_results 2>/dev/null)
SCANEOF
                echo "  connected SSID seen on : ${_n24} x 2.4GHz BSS, ${_n5} x 5GHz BSS"
                [ "$_n24" -gt 0 ] && [ "$_n5" -gt 0 ] && \
                    echo "  NOTE: mixed-band network - 5GHz association here can exceed the DHCP window"
            fi
        fi
        echo "  networks in last scan : $(wpa_cli -i "$_if" scan_results 2>/dev/null | grep -vc '^bssid')"
    else
        if command -v wpa_cli >/dev/null 2>&1; then
            echo "  wpa_supplicant not running - no association state available"
        else
            echo "  wpa_cli absent - no association state available"
        fi
    fi
    if command -v ifconfig >/dev/null 2>&1; then
        echo "--- ifconfig -a ---"
        ifconfig -a 2>&1 | redact_mac | redact_ip6 | sed 's/^/  /'
    fi

    echo
    echo "==== wifi: address / route / dns ===="
    # Separates "no wifi" from "wifi but no DHCP", which are different bugs with
    # different owners and look identical from the menu.
    if command -v ip >/dev/null 2>&1 && [ -n "$_if" ]; then
        # IPv4 and link state only. A global IPv6 address, and the /64 prefix
        # inside it, identify the user's connection at least as precisely as a
        # MAC - and none of it diagnoses anything on these devices. Count them
        # so "v6 came up" is still visible, and print none of them.
        ip addr show "$_if" 2>/dev/null | grep -v '^ *inet6 \|^ *valid_lft' \
            | redact_mac | sed 's/^/  /'
        echo "  ipv6 addresses : $(ip addr show "$_if" 2>/dev/null | grep -c '^ *inet6 ') (values withheld)"
        echo "  routes:"; ip route 2>/dev/null | sed 's/^/    /'
    fi
    # Capture first: a pipeline ending in head/sed exits 0 on empty input, so
    # the usual `... || echo none` never fires and the field prints blank.
    _dhcp=$(ps 2>/dev/null | grep -E '[u]dhcpc|[d]hcpcd|[d]hclient' | head -1 | sed 's/^ *//')
    echo "  dhcp client : ${_dhcp:-not running}"
    if [ -L /etc/resolv.conf ]; then
        echo "  /etc/resolv.conf -> $(readlink /etc/resolv.conf 2>/dev/null)"
    fi
    echo "  nameservers : $(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null || echo 0) configured"

    echo
    echo "==== wifi: bluetooth half ===="
    # RTL8821CS is one die carrying WiFi and Bluetooth on shared VBAT, VDDIO and
    # a shared 32.768kHz clock, with separate enable pins. The supported bring-up
    # order is WiFi first - muOS loads the network module before starting
    # bluetooth and derives the BT MAC from wlan0's. BT up with no wlan means
    # that order was inverted, which is worth eliminating before chasing the
    # radio itself.
    echo "  rtk_hciattach running : $(ps 2>/dev/null | grep -c '[r]tk_hciattach')"
    echo "  bluetoothd running    : $(ps 2>/dev/null | grep -c '[b]luetoothd')"
    if [ -n "$_rk_b_on" ] && [ -z "$_if" ]; then
        echo "  ORDER VIOLATED: bluetooth is unblocked and there is no wlan"
        echo "  interface. Eliminate this before drawing any conclusion about"
        echo "  the radio - block bluetooth, reboot, and retry."
    fi

    echo
    echo "==== wifi: spruce side ===="
    echo "wifi flag in system json : $(jq -r '.wifi // "<absent>"' "$SYSTEM_JSON" 2>/dev/null || echo '<unreadable>')"
    # spruce's own belief about the radio, which disable_wifi/enable_wifi set.
    # Disagreeing with the interface state above is itself the bug.
    [ -f /tmp/wifion ]  && echo "/tmp/wifion              : present (spruce believes WiFi is ON)"
    [ -f /tmp/wifioff ] && echo "/tmp/wifioff             : present (spruce believes WiFi is OFF)"
    [ -f /tmp/wifion ] || [ -f /tmp/wifioff ] || echo "wifi flag files          : neither /tmp/wifion nor /tmp/wifioff present"
    if [ -f "$WPA_SUPPLICANT_FILE" ]; then
        # Count only. The file holds plaintext PSKs and SSIDs and must never be
        # printed, not even the ssid= lines.
        echo "wpa_supplicant.conf      : present, $(grep -c '^[[:space:]]*network=' "$WPA_SUPPLICANT_FILE" 2>/dev/null) network block(s)"
        echo "  ctrl_interface set     : $(grep -qm1 '^ctrl_interface=' "$WPA_SUPPLICANT_FILE" 2>/dev/null && echo yes || echo NO)"
        echo "  update_config set      : $(grep -qm1 '^update_config=1' "$WPA_SUPPLICANT_FILE" 2>/dev/null && echo yes || echo no)"
    else
        echo "wpa_supplicant.conf      : MISSING ($WPA_SUPPLICANT_FILE)"
    fi
    echo "running processes:"
    _procs=$(ps 2>/dev/null | grep -iE "wpa_supplicant|dhclient|udhcpc|connman" | grep -v grep)
    if [ -n "$_procs" ]; then echo "$_procs" | sed 's/^/  /'; else echo "  none running"; fi
    # BaseOS boot markers, in seconds since kernel start. rcS loads the radio
    # module in the background and waits for the interface, so these say whether
    # that ever completed.
    for m in /run/boot-rcS-start /run/boot-rcS-done /run/boot-frontend-exec; do
        [ -f "$m" ] && echo "${m##*/} : $(cat "$m" 2>/dev/null)"
    done

    echo
    echo "==== wifi: kernel log ===="
    # mmc/sdio belong here as much as the driver names do. On SDIO parts the
    # radio can fail below the driver - "mmc2: error -110 whilst initialising
    # SDIO card" is the whole diagnosis, and the driver still reports a clean
    # "module init ret=0" right before it. Without those patterns the single
    # most useful line lands in some other section's dmesg tail by luck, or not
    # at all, and the report looks like a driver that loaded fine.
    _klog=$(dmesg 2>/dev/null | grep -iE 'wlan|wifi|nl80211|cfg80211|firmware|8188|8821|8723|aic|mmc[0-9]|sdio|sunxi-mmc|sunxi-rfkill' | tail -60)
    if [ -n "$_klog" ]; then echo "$_klog" | redact_mac | sed 's/^/  /'; else echo "  <nothing matched>"; fi
} > "$device_state" 2>&1

7zr a -spf2 "$output7z" \
            -i'!/mnt/SDCARD/Saves/*.json' \
            -i'!/mnt/SDCARD/Saves/cache/*.json' \
            -i'!/mnt/SDCARD/Saves/spruce/*.log' \
            -i'!/mnt/SDCARD/Saves/spruce/*.json' \
            -i'!/mnt/SDCARD/RetroArch/.retroarch/logs/*' \
            -i'!/mnt/SDCARD/App/*/log.txt' \
            -i'!/mnt/SDCARD/App/*/*/log.txt' \
            -i'!/mnt/SDCARD/spruce/spruce'

log_message "Debug: Logs and configs saved to ${output7z}"
