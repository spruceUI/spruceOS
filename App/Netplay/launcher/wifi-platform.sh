#!/bin/sh
#
# Everything this pak knows about how a given platform runs its WiFi client
# stack, in one place.
#
# Why a table rather than probing: the pak shipped a single implementation built
# from the two devices it was developed on (Brick, A30), and every assumption in
# it - `iw` for association, `udhcpc` for DHCP, `/etc/wifi/wifi_init.sh` for
# bring-up - is false on at least one of the platforms it claims to support.
# None of those failed loudly. `iw dev wlan0 link` on a device with no `iw`
# prints nothing and exits non-zero, which is indistinguishable from "not
# associated", so the H700 sat in a 5x11s join loop that could never succeed and
# then "restored" WiFi into a state with no DHCP client running at all. Probing
# harder would not have helped: the answers are knowable, and where they are
# knowable they should be written down.
#
# Sourced for its functions, or run directly as a dispatcher so the C app can
# reach the same implementations:
#
#   . wifi-platform.sh          -> np_* functions
#   sh wifi-platform.sh assoc [SSID]
#
# Expects PLATFORM and (for the SD-card wifi_init.sh platforms) SYSTEM_PATH.
#
# Verified sources for the table below:
#   tg5040/tg5050  NextUI skeleton/SYSTEM/tg5040/etc/wifi/wifi_init.sh
#   my282          NextUI skeleton/SYSTEM/my282/etc/wifi/wifi_init.sh
#   my355          NextUI-my355 skeleton/SYSTEM/my355/etc/wifi/wifi_init.sh
#   h700           NextUI-h700 skeleton/SYSTEM/h700/etc/wifi/wifi_init.sh
#                  + docs/h700-port/{00-device-facts,07-wifi-bluetooth}.md
#
# Anything not verified is left as "auto" rather than guessed. An auto entry
# degrades to the old probe-and-hope behaviour, which is the correct default for
# a platform nobody has measured - but it is visible here as a gap rather than
# hidden as an assumption.

: "${PLATFORM:=tg5040}"
: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${SYSTEM_PATH:=$SDCARD_PATH/.system/$PLATFORM}"

NP_WIFI_IF="${NP_WIFI_IF:-wlan0}"
# Overridable so the process-discovery paths below are testable off-device; the
# -C spelling this has to parse is the one that was silently unhandled.
NP_PROC="${NP_PROC:-/proc}"

###########################################################################
# the table
#
#   NP_ASSOC     iw | wpa_cli | auto     how to ask "are we associated"
#   NP_DHCP      udhcpc | dhclient | dhcpcd | auto
#   NP_DHCP_ARGS extra arguments for the DHCP client (my282's -s script)
#   NP_INIT      path to the platform's wifi_init.sh, or empty
#   NP_HOOK      1 if a `wpa_cli -a <script>` DHCP hook must be replayed with
#                the supplicant (H700 drives DHCP entirely from that hook)
#   NP_PS        nl80211 | rtw-reload | rtw-cycle    how radio power save is
#                switched: at runtime through nl80211, only by reloading the
#                driver (H700's 8821cs), or by power-cycling the radio with
#                the driver's parameters changed (the Mini Flip's 8188fu)
#   NP_CTRL      default supplicant ctrl_interface when none is running
###########################################################################

np_platform_profile() {
	NP_ASSOC=auto
	NP_DHCP=auto
	NP_DHCP_ARGS=
	NP_INIT=
	NP_HOOK=0
	NP_PS=nl80211
	NP_CTRL=

	case "$PLATFORM" in
	tg5040|tg5050)
		# Stock TrimUI ships its own /etc/wifi/wifi_init.sh and NextUI installs
		# a second copy under SYSTEM_PATH. They are different files; the stock
		# one is what this pak has always used here, so it stays first.
		NP_ASSOC=iw
		NP_DHCP=udhcpc
		NP_INIT=/etc/wifi/wifi_init.sh
		NP_CTRL=/etc/wifi/sockets
		;;
	my282)
		# No /etc/wifi at all - assuming there was one is what broke the A30
		# once already. udhcpc needs the platform's own lease script, or the
		# lease is negotiated and never applied to the interface.
		NP_ASSOC=iw
		NP_DHCP=udhcpc
		NP_DHCP_ARGS="-s $SYSTEM_PATH/etc/wifi/udhcpc.script"
		NP_INIT="$SYSTEM_PATH/etc/wifi/wifi_init.sh"
		NP_CTRL=/tmp/nextui-wifi
		;;
	my355)
		# dhcpcd, managed through an init script. Running udhcpc here puts two
		# DHCP clients on wlan0 fighting over the address - a conflict the
		# platform removed from its own bring-up deliberately. `iw` presence is
		# not confirmed on this image, so association stays auto.
		NP_DHCP=dhcpcd
		NP_INIT="$SYSTEM_PATH/etc/wifi/wifi_init.sh"
		NP_CTRL=/var/run/wpa_supplicant
		;;
	my285)
		# The Miyoo Mini Flip, on spruce only (spruce's MiyooMini). spruce's
		# network/wifi.sh owns the supplicant and udhcpc; its udhcpc needs
		# the firmware's own lease script.
		NP_DHCP=udhcpc
		NP_DHCP_ARGS="-s /etc/init.d/udhcpc.script"
		NP_PS=rtw-cycle
		NP_RTW_MODULE=8188fu
		NP_RTW_PS_INFO=/proc/net/rtl8188fu/$NP_WIFI_IF/ps_info
		;;
	h700)
		# No iw. DHCP is driven entirely by a `wpa_cli -a` action script, so
		# restoring the supplicant without also restoring that hook leaves an
		# associated interface that will never get an address again. The
		# client differs by firmware - dhclient on the Ubuntu rootfs, udhcpc
		# on base OS 1.4.0, as the action script itself probes - so take
		# whichever is installed.
		NP_ASSOC=wpa_cli
		NP_DHCP=auto
		NP_INIT="$SYSTEM_PATH/etc/wifi/wifi_init.sh"
		NP_HOOK=1
		NP_PS=rtw-reload
		NP_CTRL=/tmp/wifi/sockets
		;;
	esac

	[ -n "$NP_INIT" ] && [ ! -f "$NP_INIT" ] && NP_INIT=
	return 0
}

np_have() { command -v "$1" >/dev/null 2>&1; }

# Is this /proc entry the named process? Reads comm with the shell's `read`
# builtin - no fork - so a scan of a few hundred processes costs no processes.
#
# It matters: np_ctrl_dir is called once per second from the app's restore loop,
# and forking `tr` per PID over an Ubuntu process table turned a single `iw`
# call into several hundred forks a second. comm is truncated to 15 characters,
# which both names of interest fit inside. Where comm is unreadable we say yes
# and let the caller's cmdline check decide, rather than skipping the process.
np_is_proc() {
	[ -r "$1/comm" ] || return 0
	read -r _comm < "$1/comm" 2>/dev/null || return 0
	[ "$_comm" = "$2" ]
}

###########################################################################
# supplicant control socket
#
# The running supplicant is the truth; the table is the fallback for when none
# is running. That fallback used to be a hardcoded /var/run/wpa_supplicant,
# which is right on exactly one of the five platforms.
###########################################################################

np_ctrl_dir() {
	if [ -n "${NP_CTRL_CACHE:-}" ]; then
		printf '%s\n' "$NP_CTRL_CACHE"
		return 0
	fi
	np_platform_profile
	_ctrl=""
	_conf=""
	for _d in "$NP_PROC"/[0-9]*; do
		np_is_proc "$_d" wpa_supplicant || continue
		_a0=$( { tr '\0' '\n' < "$_d/cmdline"; } 2>/dev/null | head -1)
		case "$_a0" in
		*/wpa_supplicant|wpa_supplicant) ;;
		*) continue ;;
		esac
		# Three spellings occur across these platforms: `-O/etc/wifi/sockets`
		# joined (tg5040), `-c /path` split (my282), `-C /tmp/wifi/sockets`
		# split (h700). Handling only the first two found nothing on the H700.
		_want=""
		for _a in $( { tr '\0' '\n' < "$_d/cmdline"; } 2>/dev/null); do
			if [ -n "$_want" ]; then
				case "$_want" in
				O|C) _ctrl="$_a" ;;
				c)   _conf="$_a" ;;
				esac
				_want=""
				continue
			fi
			case "$_a" in
			-O|-C) _want=O ;;
			-c)    _want=c ;;
			-O?*)  _ctrl=${_a#-O} ;;
			-C?*)  _ctrl=${_a#-C} ;;
			-c?*)  _conf=${_a#-c} ;;
			esac
		done
		break
	done
	if [ -z "$_ctrl" ] && [ -n "$_conf" ] && [ -f "$_conf" ]; then
		_ctrl=$(sed -n 's/^ctrl_interface=\(DIR=\)\?//p' "$_conf" 2>/dev/null |
			sed 's/ .*//' | head -1)
	fi
	[ -n "$_ctrl" ] || _ctrl="$NP_CTRL"
	[ -n "$_ctrl" ] || _ctrl=/var/run/wpa_supplicant
	NP_CTRL_CACHE="$_ctrl"
	printf '%s\n' "$_ctrl"
}

###########################################################################
# association
###########################################################################

# Echoes the SSID we are associated to, or nothing.
np_assoc_ssid() {
	np_platform_profile
	case "$NP_ASSOC" in
	iw)      np_assoc_ssid_iw ;;
	wpa_cli) np_assoc_ssid_wpa ;;
	*)
		# `iw` present and answering wins, because it is what this pak was
		# built and measured against. It is only bypassed when it cannot
		# answer at all - missing, or printing nothing for an interface it
		# does not know - which is precisely the H700 case and is otherwise
		# indistinguishable from "not associated".
		if np_have iw && [ -n "$(iw dev "$NP_WIFI_IF" link 2>/dev/null)" ]; then
			np_assoc_ssid_iw
		else
			np_assoc_ssid_wpa
		fi
		;;
	esac
}

np_assoc_ssid_iw() {
	iw dev "$NP_WIFI_IF" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -1
}

np_assoc_ssid_wpa() {
	np_have wpa_cli || return 0
	_st=$(wpa_cli -p "$(np_ctrl_dir)" -i "$NP_WIFI_IF" status 2>/dev/null)
	# COMPLETED only. wpa_cli reports ASSOCIATED before the 4-way handshake
	# finishes, and a DHCP request sent in that gap is dropped - the same trap
	# the iw path documents and works around with a sleep.
	case "$_st" in
	*wpa_state=COMPLETED*) printf '%s\n' "$_st" | sed -n 's/^ssid=//p' | head -1 ;;
	esac
}

# Make the running supplicant read its config again, which also clears a
# network's TEMP-DISABLED back-off. A host whose AP held the radio's one channel
# while the house network moved to another (2026-10-26: the router went from
# channel 10 to 7 overnight) failed every rejoin, and after the AP was gone the
# supplicant stayed backed off: enable_network and reassociate did not lift it,
# reconfigure did. Nothing to do without wpa_cli.
np_supplicant_reconfigure() {
	np_have wpa_cli || return 1
	np_platform_profile
	wpa_cli -p "$(np_ctrl_dir)" -i "$NP_WIFI_IF" reconfigure >/dev/null 2>&1
}

# Which association probe this device will actually use: iw, wpa_cli, or none.
# "none" is the answer that matters - it means nothing here can tell associated
# from not, which is the state the H700 shipped in and which every timeout in
# this pak silently mistook for "the network is not there".
np_assoc_kind() {
	np_platform_profile
	case "$NP_ASSOC" in
	iw)      np_have iw      && { echo iw; return 0; } ;;
	wpa_cli) np_have wpa_cli && { echo wpa_cli; return 0; } ;;
	esac
	np_have iw      && { echo iw; return 0; }
	np_have wpa_cli && { echo wpa_cli; return 0; }
	echo none
}

# np_assoc [SSID] - associated at all, or to this SSID specifically.
np_assoc() {
	_cur=$(np_assoc_ssid)
	[ -n "$_cur" ] || return 1
	[ -n "${1:-}" ] || return 0
	[ "$_cur" = "$1" ]
}

np_has_ip() {
	ip -4 addr show "$NP_WIFI_IF" 2>/dev/null | grep -q 'inet '
}

np_ip() {
	ip -4 addr show "$NP_WIFI_IF" 2>/dev/null |
		sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1
}

###########################################################################
# DHCP
#
# Selection is by what the platform uses, not by what happens to be first on
# PATH: busybox udhcpc exists on the Flip alongside dhcpcd, and running it
# there recreates the two-clients-fighting-over-wlan0 bug that platform
# already fixed once.
###########################################################################

np_dhcp_first_present() {
	for _c in udhcpc dhclient dhcpcd; do
		np_have "$_c" && { printf '%s\n' "$_c"; return 0; }
	done
	printf 'none\n'
}

np_dhcp_kind() {
	np_platform_profile
	if [ "$NP_DHCP" = auto ]; then
		np_dhcp_first_present
		return 0
	fi
	# A named client that is not installed is a packaging fault, not a reason
	# to silently do nothing - but some address beats none, so say so and take
	# whatever is there. Deliberately not recursive: re-entering would re-read
	# the table and reset NP_DHCP to the name that is already known missing.
	if np_have "$NP_DHCP"; then
		printf '%s\n' "$NP_DHCP"
	else
		echo "[netplay-wifi] $PLATFORM expects $NP_DHCP, which is not installed" >&2
		np_dhcp_first_present
	fi
}

np_dhcp_stop() {
	np_platform_profile
	case "$(np_dhcp_kind)" in
	udhcpc)   killall -q udhcpc 2>/dev/null ;;
	dhclient) dhclient -r "$NP_WIFI_IF" >/dev/null 2>&1; killall -q dhclient 2>/dev/null ;;
	dhcpcd)   dhcpcd -k "$NP_WIFI_IF" >/dev/null 2>&1 || killall -q dhcpcd 2>/dev/null ;;
	esac
	return 0
}

# Ask for a lease. Returns immediately; the caller polls np_has_ip. Blocking
# here is what used to freeze the UI for ~24s: busybox udhcpc pauses -T seconds
# between discovers and multiplies -t straight into wall clock.
#
#   np_dhcp_start             one-shot - we want an address now and will tear
#                             this down again shortly (joining an ad hoc net)
#   np_dhcp_start persistent  leave a renewing client behind - we are handing
#                             the radio back to the user and will not be here
#                             when the lease expires
#
# The distinction only bites udhcpc: `-n -q` exits as soon as it has a lease, so
# every restore this pak has ever done left the Brick holding an address with
# nothing to renew it. dhclient and dhcpcd daemonise and renew either way.
np_dhcp_start() {
	np_platform_profile
	case "$(np_dhcp_kind)" in
	udhcpc)
		# shellcheck disable=SC2086
		if [ "${1:-oneshot}" = persistent ]; then
			# Backgrounded even though -b implies it: busybox -b only forks
			# when the lease *fails*, and blocks until it has one otherwise -
			# which in the app's restore loop is a frozen UI.
			udhcpc -i "$NP_WIFI_IF" -b $NP_DHCP_ARGS >/dev/null 2>&1 &
		else
			udhcpc -i "$NP_WIFI_IF" -n -q -t 3 -T 2 $NP_DHCP_ARGS >/dev/null 2>&1 &
		fi
		;;
	dhclient)
		dhclient -nw "$NP_WIFI_IF" >/dev/null 2>&1 &
		;;
	dhcpcd)
		dhcpcd -n "$NP_WIFI_IF" >/dev/null 2>&1 &
		;;
	*)
		echo "[netplay-wifi] no DHCP client on $PLATFORM" >&2
		return 1
		;;
	esac
	return 0
}

###########################################################################
# spruce: ad hoc through spruce's own supplicant
#
# spruce adopts any wpa_supplicant it finds on wlan0 running another config:
# it copies that config's networks into the user's saved networks and starts
# its own (enable_wifi, which runs on every game exit). Replacing the
# supplicant with ours, as everywhere else, got the ad hoc network saved with
# priority 99 - the guest went back to it after the session, and would again
# whenever it was in range. So on spruce the guest never replaces anything:
# the ad hoc network is added to spruce's supplicant at runtime, never saved,
# and selected; leaving removes it and re-enables the saved networks. spruce's
# own DHCP client stays and is told to start over.
###########################################################################

np_is_spruce() {
	[ "${NETPLAY_FIRMWARE:-}" = spruce ] || [ -f "$SDCARD_PATH/spruce/scripts/wifi.sh" ]
}

np_spruce_cli() {
	_sc_dir=$(np_ctrl_dir)
	wpa_cli ${_sc_dir:+-p "$_sc_dir"} -i "$NP_WIFI_IF" "$@" 2>/dev/null
}

# Netplay's networks in the running supplicant, by id.
np_spruce_adhoc_ids() {
	np_spruce_cli list_networks | awk -F'\t' 'NR > 1 && $2 ~ /^netplay-/ { print $1 }'
}

# np_spruce_join SSID PSK - both already checked to be [A-Za-z0-9].
np_spruce_join() {
	for _id in $(np_spruce_adhoc_ids); do np_spruce_cli remove_network "$_id" >/dev/null; done
	_id=$(np_spruce_cli add_network | tail -1)
	case "$_id" in ''|*[!0-9]*) echo "[netplay-wifi] spruce's supplicant did not answer" >&2; return 1 ;; esac
	np_spruce_cli set_network "$_id" ssid "\"$1\"" | grep -q OK &&
	np_spruce_cli set_network "$_id" psk "\"$2\"" | grep -q OK &&
	np_spruce_cli set_network "$_id" key_mgmt WPA-PSK | grep -q OK &&
	np_spruce_cli select_network "$_id" | grep -q OK
}

# select_network disabled every other network; put them back.
np_spruce_leave() {
	for _id in $(np_spruce_adhoc_ids); do np_spruce_cli remove_network "$_id" >/dev/null; done
	np_spruce_cli enable_network all >/dev/null
	np_spruce_cli reassociate >/dev/null
}

# A lease for the network just joined or rejoined: release, then renew, so
# spruce's client starts over instead of renewing the old address. One is
# started if none is running.
np_spruce_renew() {
	_pids=$(pidof udhcpc)
	if [ -z "$_pids" ]; then
		np_dhcp_start persistent
		return
	fi
	# shellcheck disable=SC2086
	kill -USR2 $_pids 2>/dev/null
	sleep 0.2
	# shellcheck disable=SC2086
	kill -USR1 $_pids 2>/dev/null
	return 0
}

###########################################################################
# platform bring-up script
###########################################################################

# Echoes the platform's wifi_init.sh, or nothing. Never the pak's guess: the
# hardcoded /etc/wifi/wifi_init.sh is present on tg50xx and absent on all three
# of the others, where it silently disabled this whole recovery route.
np_wifi_init_path() { np_platform_profile; printf '%s\n' "$NP_INIT"; }

np_wifi_init() {
	np_platform_profile
	[ -n "$NP_INIT" ] || return 1
	SYSTEM_PATH="$SYSTEM_PATH" SDCARD_PATH="$SDCARD_PATH" \
		sh "$NP_INIT" "$1" >/dev/null 2>&1
	return 0
}

###########################################################################
# the supplicant's DHCP hook
#
# H700 runs `wpa_cli -B -p <sockets> -i wlan0 -a /tmp/wifi/wpa_action.sh`
# alongside the supplicant, and that action script is the only thing that ever
# runs dhclient. Killing the supplicant takes the hook with it, so replaying
# only the supplicant leaves a radio that associates and never gets an address
# again - for every future reassociation, not just ours. That is why the H700
# needed a reboot after each session.
#
# A no-op on every platform with no such process, so it costs nothing to run
# unconditionally.
###########################################################################

np_hook_capture() {
	[ -n "${1:-}" ] || return 1
	for _d in "$NP_PROC"/[0-9]*; do
		np_is_proc "$_d" wpa_cli || continue
		_a0=$( { tr '\0' '\n' < "$_d/cmdline"; } 2>/dev/null | head -1)
		case "$_a0" in
		*/wpa_cli|wpa_cli) ;;
		*) continue ;;
		esac
		# Only an action-script instance is worth replaying; an interactive or
		# one-shot wpa_cli is not part of the platform's bring-up.
		case " $( { tr '\0' ' ' < "$_d/cmdline"; } 2>/dev/null) " in
		*" -a "*)
			{ tr '\0' ' ' < "$_d/cmdline" > "$1"; } 2>/dev/null
			echo >> "$1"
			return 0
			;;
		esac
	done
	return 1
}

np_hook_replay() {
	[ -n "${1:-}" ] && [ -f "$1" ] || return 1
	_cmd=$(head -1 "$1" 2>/dev/null)
	[ -n "$_cmd" ] || return 1
	killall -q wpa_cli 2>/dev/null
	case " $_cmd " in
	*" -B "*) ;;
	*) _cmd="$_cmd -B" ;;
	esac
	sh -c "$_cmd" >/dev/null 2>&1
	return 0
}

###########################################################################
# power save
###########################################################################

# `iw` where the image has it; otherwise the pak's own nl80211 helper, which is
# the same two netlink calls `iw` would make, for images that ship without iw.
np_wifips_helper() {
	if [ -n "${NP_WIFIPS:-}" ]; then
		_h="$NP_WIFIPS"
	elif [ -n "${NETPLAY_PAK:-}" ]; then
		_h="$NETPLAY_PAK/bin/$PLATFORM/netplay-wifips.elf"
	else
		# Run as a program from the pak's launcher/ directory.
		_h="$(dirname -- "$0")/../bin/$PLATFORM/netplay-wifips.elf"
	fi
	[ -x "$_h" ] && echo "$_h"
}

# H700's 8821cs vendor driver accepts nl80211 power save and reports it back,
# but never applies it: the radio stays in LPS at whatever rtw_power_mgnt the
# module was loaded with (2, maximum, from BaseOS's bare insmod). The module
# parameter is read once at load, so the only real switch is a reload. It then
# holds until the next boot - WiFi restarts and sleep do not reload the driver.
: "${NP_RTW_MODULE:=8821cs}"
: "${NP_RTW_KO:=/lib/modules/8821cs.ko}"
: "${NP_RTW_PS_INFO:=/proc/net/rtl8821cs/$NP_WIFI_IF/ps_info}"
: "${NP_RTW_RF:=/sys/class/misc/sunxi-wlan/rf-ctrl}"
: "${NP_RTW_SLOW_FLAG:=/data/wifi-slow-radio}"
: "${NP_SYS_NET:=/sys/class/net}"

# The driver's own view: "LPS mode: MAX" (or MIN/DTIM/SELF_DEFINED) is power
# save, anything else is the active mode a reload with rtw_power_mgnt=0 gives.
np_rtw_powersave_get() {
	_mode=$(sed -n 's/^ *LPS mode: *//p' "$NP_RTW_PS_INFO" 2>/dev/null | head -1)
	case "$_mode" in
	"") return 1 ;;
	MAX*|MIN*|DTIM*|SELF*) echo on ;;
	*) echo off ;;
	esac
}

np_rtw_log() { echo "wifi-platform: $*" >&2; }

# spruce's one way to change the radio. It moved from scripts/ to
# scripts/network/; with neither found the reload below ran under spruce's live
# supplicant and left the H700 off the network.
np_spruce_wifi_script() {
	for _s in "$SDCARD_PATH/spruce/scripts/network/wifi.sh" "$SDCARD_PATH/spruce/scripts/wifi.sh"; do
		[ -f "$_s" ] && { echo "$_s"; return 0; }
	done
	return 1
}

# The Miyoo Mini Flip's RTL8188FU, as NextUI's my285 network.sh found it:
# rtw_power_mgnt and rtw_ips_mode are module parameters the driver latches when
# the USB device probes, and the device only probes when axp_test powers the
# radio's rail. So power-save off is: rail off, the parameters written while it
# is off, rail on - spruce's wifi.sh apply does that last step itself whenever
# wlan0 is missing - then nl80211 power save off once the interface is up,
# because a kernel built with CFG80211_DEFAULT_PS turns it back on at every
# interface up and the driver leaves LPS only on an explicit "off".
: "${NP_AXP_TEST:=/customer/app/axp_test}"
np_rtl8188_cycle() {  # np_rtl8188_cycle on|off
	case "$1" in on) _mgnt=2; _ips=1 ;; off) _mgnt=0; _ips=0 ;; *) return 2 ;; esac
	_params=${NP_RTW_PARAMS:-/sys/module/$NP_RTW_MODULE/parameters}
	[ -w "$_params/rtw_power_mgnt" ] || { np_rtw_log "no $NP_RTW_MODULE parameters to write"; return 1; }
	[ -x "$NP_AXP_TEST" ] || { np_rtw_log "no $NP_AXP_TEST to power the radio"; return 1; }
	_spruce_wifi=
	np_is_spruce && _spruce_wifi=$(np_spruce_wifi_script)

	np_rtw_log "power-cycling $NP_RTW_MODULE with rtw_power_mgnt=$_mgnt rtw_ips_mode=$_ips"
	if [ -n "$_spruce_wifi" ]; then
		sh "$_spruce_wifi" suspend --wait >/dev/null 2>&1
	else
		np_wifi_init stop
	fi
	ifconfig "$NP_WIFI_IF" down 2>/dev/null
	"$NP_AXP_TEST" wifioff >/dev/null 2>&1
	_w=0
	while [ -d "$NP_SYS_NET/$NP_WIFI_IF" ] && [ "$_w" -lt 40 ]; do sleep 0.25; _w=$((_w + 1)); done
	[ -d "$NP_SYS_NET/$NP_WIFI_IF" ] && np_rtw_log "$NP_WIFI_IF still present after wifioff; the new values may not latch"
	echo "$_mgnt" > "$_params/rtw_power_mgnt" 2>/dev/null
	echo "$_ips" > "$_params/rtw_ips_mode" 2>/dev/null
	if [ -n "$_spruce_wifi" ]; then
		sh "$_spruce_wifi" apply --wait >/dev/null 2>&1
	else
		"$NP_AXP_TEST" wifion >/dev/null 2>&1
		_w=0
		while [ ! -d "$NP_SYS_NET/$NP_WIFI_IF" ] && [ "$_w" -lt 40 ]; do sleep 0.25; _w=$((_w + 1)); done
		np_wifi_init start
	fi
	_w=0
	while ! np_has_ip && [ "$_w" -lt 30 ]; do sleep 1; _w=$((_w + 1)); done
	if [ "$1" = off ]; then
		_h=$(np_wifips_helper) && "$_h" "$NP_WIFI_IF" off >/dev/null 2>&1
	fi
	np_has_ip || { np_rtw_log "radio power-cycled but no address yet"; return 3; }
	np_rtw_log "power-cycled, power save $(np_powersave_get), address $(np_ip)"
	return 0
}

# One load attempt, with BaseOS rcS's own preparation: with the radio powered
# off, ask the platform to drop the stale SDIO card before the driver powers it
# up again, or the probe races the driver's own rescan.
np_rtw_load() {  # np_rtw_load <rtw_power_mgnt> <quarter-seconds to wait>
	if [ -w "$NP_RTW_RF/scan_device" ] && read -r _pw < "$NP_RTW_RF/power_state" 2>/dev/null &&
	   [ "$_pw" = 0 ]; then
		printf '1\n' > "$NP_RTW_RF/scan_device"
		_w=0
		for _card in /sys/bus/sdio/devices/*; do
			while [ -d "$_card" ] && [ "$_w" -lt 20 ]; do sleep 0.05; _w=$((_w + 1)); done
		done
	fi
	insmod "$NP_RTW_KO" "rtw_power_mgnt=$1" 2>/dev/null
	_w=0
	while [ ! -d "$NP_SYS_NET/$NP_WIFI_IF" ] && [ "$_w" -lt "$2" ]; do
		sleep 0.25; _w=$((_w + 1))
	done
	[ -d "$NP_SYS_NET/$NP_WIFI_IF" ]
}

# Reload the driver with power save on or off, then bring the platform's client
# stack back. Several seconds by design: the radio is held powered off for as
# long as BaseOS holds it at boot, longer on units it has marked slow to reset,
# because a quick re-power is exactly what those units fail on.
np_rtw_reload() {  # np_rtw_reload on|off
	np_platform_profile
	[ "$NP_PS" = rtw-cycle ] && { np_rtl8188_cycle "$1"; return; }
	[ "$NP_PS" = rtw-reload ] || return 1
	case "$1" in on) _mgnt=2 ;; off) _mgnt=0 ;; *) return 2 ;; esac
	[ -f "$NP_RTW_KO" ] || { np_rtw_log "no $NP_RTW_KO"; return 1; }
	_hold=2; [ -e "$NP_RTW_SLOW_FLAG" ] && _hold=5

	# spruce has no NextUI wifi_init.sh: stopping nothing pulled the driver out
	# from under its supplicant and left the radio down for good. Its wifi.sh
	# is the one way to change the radio there; `apply` loads the driver only
	# when it is not loaded, so the one loaded below keeps its power setting.
	_spruce_wifi=
	np_is_spruce && _spruce_wifi=$(np_spruce_wifi_script)

	np_rtw_log "reloading $NP_RTW_MODULE with rtw_power_mgnt=$_mgnt (radio off ${_hold}s)"
	if [ -n "$_spruce_wifi" ]; then
		sh "$_spruce_wifi" suspend --wait >/dev/null 2>&1
	else
		np_wifi_init stop
	fi
	rmmod "$NP_RTW_MODULE" 2>/dev/null
	sleep "$_hold"
	if ! np_rtw_load "$_mgnt" 40; then
		np_rtw_log "no $NP_WIFI_IF after the first load; retrying after a longer power-off"
		rmmod "$NP_RTW_MODULE" 2>/dev/null
		sleep 5
		np_rtw_load "$_mgnt" 40 || { np_rtw_log "driver did not come back"; return 1; }
	fi
	rfkill unblock wifi 2>/dev/null
	ip link set "$NP_WIFI_IF" up 2>/dev/null
	if [ -n "$_spruce_wifi" ]; then
		sh "$_spruce_wifi" apply --wait >/dev/null 2>&1
	else
		np_wifi_init start
	fi
	_w=0
	while ! np_has_ip && [ "$_w" -lt 30 ]; do sleep 1; _w=$((_w + 1)); done
	np_has_ip || { np_rtw_log "driver reloaded but no address yet"; return 3; }
	np_rtw_log "reloaded, power save $(np_rtw_powersave_get), address $(np_ip)"
	return 0
}

np_powersave_get() {
	np_platform_profile
	if [ "$NP_PS" = rtw-reload ]; then
		np_rtw_powersave_get
		return
	fi
	if [ "$NP_PS" = rtw-cycle ]; then
		# The driver's own LPS mode when it reports one; else the latched
		# parameter, which is what a power-cycle sets.
		np_rtw_powersave_get && return 0
		case "$(cat "${NP_RTW_PARAMS:-/sys/module/$NP_RTW_MODULE/parameters}/rtw_power_mgnt" 2>/dev/null)" in
		0) echo off ;; "") return 1 ;; *) echo on ;;
		esac
		return 0
	fi
	if np_have iw; then
		iw dev "$NP_WIFI_IF" get power_save 2>/dev/null |
			sed -n 's/.*Power save: *//p' | head -1
		return 0
	fi
	_h=$(np_wifips_helper) || return 1
	"$_h" "$NP_WIFI_IF" 2>/dev/null
}

# Runtime switch. Where only a reload can change the state this succeeds only
# if the radio is already where it was asked to be, so callers re-applying
# "off" before each launch cost nothing and change nothing.
np_powersave() {
	np_platform_profile
	if [ "$NP_PS" = rtw-reload ]; then
		[ "$(np_rtw_powersave_get)" = "$1" ]
		return
	fi
	if [ "$NP_PS" = rtw-cycle ]; then
		# Cheap to repeat before every launch: an interface brought up again
		# may have had nl80211 power save switched back on.
		if [ "$1" = off ]; then
			_h=$(np_wifips_helper) && "$_h" "$NP_WIFI_IF" off >/dev/null 2>&1
		fi
		[ "$(np_powersave_get)" = "$1" ]
		return
	fi
	if np_have iw; then
		iw dev "$NP_WIFI_IF" set power_save "$1" >/dev/null 2>&1
		return 0
	fi
	_h=$(np_wifips_helper) || return 1
	"$_h" "$NP_WIFI_IF" "$1" >/dev/null 2>&1
}

# Whether turning power save off needs the slow driver reload (or power-cycle):
# yes only on such a platform whose radio is currently in power save.
np_powersave_needs_reload() {
	np_platform_profile
	case "$NP_PS" in rtw-reload|rtw-cycle) ;; *) return 1 ;; esac
	[ "$(np_powersave_get)" = on ]
}

###########################################################################
# CLI dispatcher, so the C app shares these implementations rather than
# carrying a second copy of the same table that can drift out of step.
###########################################################################

# Dispatch only when run as a program. When this file is sourced, `.` leaves the
# caller's positional parameters in place, so keying off "$1" would make
# `. wifi-platform.sh` from a script invoked with arguments fall through to the
# usage branch and exit. $0 stays the caller's path when sourced, which is the
# distinction that actually holds in dash and busybox ash.
case "$(basename -- "$0" 2>/dev/null)" in
wifi-platform.sh)
	case "${1:-}" in
	assoc)          np_assoc "${2:-}" ;;
	assoc-kind)     np_assoc_kind ;;
	assoc-ssid)     np_assoc_ssid ;;
	has-ip)         np_has_ip ;;
	ip)             np_ip ;;
	ctrl-dir)       np_ctrl_dir ;;
	supplicant-reconfigure) np_supplicant_reconfigure ;;
	dhcp-kind)      np_dhcp_kind ;;
	dhcp-start)     np_dhcp_start "${2:-oneshot}" ;;
	dhcp-stop)      np_dhcp_stop ;;
	wifi-init)      np_wifi_init "${2:-start}" ;;
	wifi-init-path) np_wifi_init_path ;;
	hook-capture)   np_hook_capture "${2:-}" ;;
	hook-replay)    np_hook_replay "${2:-}" ;;
	powersave)      np_powersave "${2:-off}" ;;
	powersave-get)  np_powersave_get ;;
	powersave-needs-reload) np_powersave_needs_reload ;;
	powersave-reload) np_rtw_reload "${2:-off}" ;;
	is-spruce)      np_is_spruce ;;
	spruce-join)    np_spruce_join "${2:-}" "${3:-}" ;;
	spruce-leave)   np_spruce_leave ;;
	spruce-renew)   np_spruce_renew ;;
	"")             : ;;
	*)              echo "usage: wifi-platform.sh <assoc|has-ip|dhcp-start|...>" >&2; exit 2 ;;
	esac
	;;
esac
