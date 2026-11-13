#!/bin/sh
#
# Get back onto the normal network if the ad hoc one goes away underneath us.
#
# The gap this closes: you join a host's network, the host powers off or ends
# its session, and nothing is running that would notice. The other three
# recovery points all need something to happen first - opening the app, starting
# a game, or pressing Restore WiFi - so sitting in the system menu you are
# stranded until you go looking.
#
# Scope is deliberately narrow:
#
#   * Started when a join succeeds, not at boot. A device that never uses ad hoc
#     never runs this, so it costs nothing to have.
#   * Exits as soon as the shared wifi_restore record is gone. It is written when we
#     take the client stack down and removed when we put it back, so the
#     watchdog's lifetime is exactly the window where stranding is possible.
#   * Exits if we are already back on a normal network, cleaning up the record.
#   * Never acts on one failed check. A host in a menu, or a moment of RF noise,
#     must not kick anyone off a working session.
#
# A reboot does not need covering: the temporary supplicant config lives in
# /tmp, so the platform's own init brings WiFi back normally on the next boot.

# Pak path as $1 when the caller knows it (the launch stub derives it from the
# session file); otherwise fall back to the environment. Relying on inherited
# SDCARD_PATH/PLATFORM alone was fragile - the stub does not export them.
if [ -n "$1" ] && [ -d "$1" ]; then
	NP="$1"
else
	: "${SDCARD_PATH:=/mnt/SDCARD}"
	: "${PLATFORM:=tg5040}"
	NP="$SDCARD_PATH/Tools/$PLATFORM/Netplay.pak"
fi
. "$NP/launcher/state-path.sh"
. "$NP/launcher/wifi-platform.sh"

RESTORE="$NETPLAY_STATE/wifi_restore"
RESTORE_HOOK="$NETPLAY_STATE/wifi_restore_hook"
LOCK="/tmp/netplay_watchdog.pid"
RESTORE_LOCK="/tmp/netplay_wifi_restore.lock"
HOST=10.0.0.1
PREFIX=netplay

INTERVAL=${NETPLAY_WATCHDOG_INTERVAL:-20}      # seconds between checks
FAILS_NEEDED=${NETPLAY_WATCHDOG_FAILS:-3}      # ~60s grace by default
MAX_CHECKS=${NETPLAY_WATCHDOG_MAX_CHECKS:-1440} # ~8h backstop

# Own our output. Callers used to redirect, which forced them to know where the
# log lives and left us tied to their descriptors.
#
# Appended across runs, because the interesting sequence spans several: a join,
# a host that disappears an hour later, the recovery. Capped so that appending
# forever cannot quietly grow a file on the card - one backup generation is
# enough to keep the run before this one.
WATCHDOG_LOG="$NETPLAY_STATE/watchdog.log"
: "${NETPLAY_WATCHDOG_LOG_MAX:=65536}"
_size=$(wc -c < "$WATCHDOG_LOG" 2>/dev/null) || _size=0
case "$_size" in ''|*[!0-9]*) _size=0 ;; esac
[ "$_size" -gt "$NETPLAY_WATCHDOG_LOG_MAX" ] &&
	mv "$WATCHDOG_LOG" "$WATCHDOG_LOG.1" 2>/dev/null
exec >>"$WATCHDOG_LOG" 2>&1

# Same HH:MM:SS.mmm shape as the C loggers so the three logs can be read
# side by side. busybox date has no %N, so milliseconds come from
# /proc/uptime's centiseconds - close enough to order events.
log() { echo "[$(date +%H:%M:%S).$(cut -d" " -f1 /proc/uptime | cut -d. -f2)0 ] [netplay-watchdog] $*"; }

# One at a time. A second join should not start a second watchdog.
# mkdir is atomic; a test-then-write is not. Two joins in quick succession both
# passed the old check before either wrote, and two watchdogs ran at once -
# visible in the log as two "watching" lines with no failures between them.
LOCKDIR=/tmp/netplay_watchdog.lock
if ! mkdir "$LOCKDIR" 2>/dev/null; then
	_old=$(cat "$LOCKDIR/pid" 2>/dev/null)
	if [ -n "$_old" ] && [ -d "/proc/$_old" ]; then
		exit 0
	fi
	rm -rf "$LOCKDIR"
	mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ > "$LOCKDIR/pid"
echo $$ > "$LOCK"          # the app reads this one
trap 'rm -rf "$LOCKDIR"; rm -f "$LOCK"' EXIT

link_up() {
	np_assoc
}

on_adhoc() {
	case "$(np_assoc_ssid)" in
	"$PREFIX"-*) return 0 ;;
	*)           return 1 ;;
	esac
}

restore_replay() {
	# Same command the app captured before it moved the client stack. Replaying
	# it verbatim is the only portable route back: /etc/wifi/wifi_init.sh exists
	# on some platforms and not others.
	_cmd=$(head -1 "$RESTORE" 2>/dev/null)
	if [ -z "$_cmd" ]; then
		log "nothing recorded to restore with"
		rm -f "$RESTORE_LOCK/pid"; rmdir "$RESTORE_LOCK" 2>/dev/null
		return 1
	fi

	killall -q wpa_supplicant 2>/dev/null
	np_dhcp_stop
	ip addr flush dev wlan0 2>/dev/null
	ip link set wlan0 up 2>/dev/null
	# Captured service commands are not guaranteed to daemonise themselves. A
	# foreground supplicant would pin the watchdog inside this command and never
	# reach DHCP or session cleanup.
	case " $_cmd " in
		*" -B "*) ;;
		*) _cmd="$_cmd -B" ;;
	esac
	sh -c "$_cmd" >/dev/null 2>&1
	# Platforms that run DHCP from a `wpa_cli -a` hook need that process back
	# too; without it the radio reassociates forever and never gets an address.
	np_hook_replay "$RESTORE_HOOK"

	_w=1
	while [ $_w -le 10 ]; do
		np_assoc && break
		sleep 1
		_w=$((_w + 1))
	done
	# Persistent: nobody is coming back to renew this one.
	np_dhcp_start persistent
	_w=1
	while [ $_w -le 10 ]; do
		np_has_ip && break
		sleep 1
		_w=$((_w + 1))
	done
}

# spruce: nothing was moved. The ad hoc network comes back out of spruce's own
# supplicant and spruce's DHCP client starts over (wifi-platform.sh).
restore_spruce() {
	np_spruce_leave
	_w=1
	while [ $_w -le 10 ]; do
		np_assoc && ! on_adhoc && break
		sleep 1
		_w=$((_w + 1))
	done
	np_spruce_renew
	sleep 1
	_w=1
	while [ $_w -le 10 ]; do
		np_has_ip && break
		sleep 1
		_w=$((_w + 1))
	done
}

restore_wifi() {
	# The setup app has a foreground restore path using the same radio and daemon
	# commands. Only one may own that transaction: otherwise each can kill the
	# supplicant the other just started. A live owner will finish (or retain the
	# breadcrumb), so the watchdog can retry on its next failure window.
	if ! mkdir "$RESTORE_LOCK" 2>/dev/null; then
		_owner=$(cat "$RESTORE_LOCK/pid" 2>/dev/null)
		if [ -n "$_owner" ] && [ -d "/proc/$_owner" ]; then
			log "wifi restoration already owned by pid $_owner"
			return 1
		fi
		rm -f "$RESTORE_LOCK/pid"
		rmdir "$RESTORE_LOCK" 2>/dev/null
		mkdir "$RESTORE_LOCK" 2>/dev/null || return 1
	fi
	echo $$ > "$RESTORE_LOCK/pid"

	if np_is_spruce; then
		restore_spruce
	else
		restore_replay || return 1
	fi

	_ip=$(np_ip)
	if [ -z "$_ip" ]; then
		log "restore attempt did not get an address - keeping recovery record"
		rm -f "$RESTORE_LOCK/pid"; rmdir "$RESTORE_LOCK" 2>/dev/null
		return 1
	fi
	log "recovered, back on wifi as $_ip"
	rm -f "$RESTORE" "$RESTORE_HOOK"

	# The ad hoc network is gone. A host lobby is persistent by design, but a
	# guest cannot continue a session whose transport and ad-hoc peer address no
	# longer exist. End only that guest's session; bindings remain installed and
	# therefore become passthrough. The role check is deliberately made after
	# recovery so this detached process cannot tear down a host session.
	_sess="$NETPLAY_STATE/session"
	if [ -f "$_sess" ] && grep -q '^role=client$' "$_sess" 2>/dev/null &&
	   grep -q '^adhoc_ssid=' "$_sess" 2>/dev/null; then
		netplay_end_session "$_sess"
		_ps="$NETPLAY_STATE/wifi_powersave"
		[ "$(head -1 "$_ps" 2>/dev/null)" = on ] && np_powersave on
		rm -f "$_ps"
		log "original wifi restored - ended guest session"
	elif [ -f "$_sess" ] && grep -q '^adhoc_ssid=' "$_sess" 2>/dev/null; then
		grep -v '^adhoc_ssid=' "$_sess" | grep -v '^adhoc_psk=' > "$_sess.tmp" 2>/dev/null &&
			mv "$_sess.tmp" "$_sess" &&
			log "preserved non-guest session and cleared obsolete ad hoc credentials"
	fi
	rm -f "$RESTORE_LOCK/pid"; rmdir "$RESTORE_LOCK" 2>/dev/null
}

log "watching (host $HOST, every ${INTERVAL}s, act after $FAILS_NEEDED failures)"

fails=0
checks=0
while :; do
	# The backstop is for a watchdog whose session went away without taking the
	# record with it. While a session is still armed this is the only thing that
	# would notice the host leaving, so keep watching: an evening's session ran
	# past the old hard 8 h stop, the host ended it an hour later, and the guest
	# sat on the dead network until the app was opened (2026-10-26).
	if [ $checks -ge $MAX_CHECKS ]; then
		[ -f "$NETPLAY_STATE/session" ] || break
		log "still armed after $checks checks - watching on"
		checks=0
	fi
	sleep $INTERVAL
	checks=$((checks + 1))

	# The session ended, or someone already put us back.
	[ -f "$RESTORE" ] || { log "no restore record - session over, exiting"; exit 0; }

	# Three states, and only one of them means "done".
	#
	# Not being on the ad hoc network is NOT the same as being home. When the
	# host's AP disappears, our supplicant is holding a config that contains
	# only that network, so it sits associated to nothing and keeps scanning -
	# which is precisely the case this watchdog exists for. Treating that as
	# "home" would delete the recovery record and leave the device stranded
	# with no breadcrumb left to recover from.
	if link_up; then
		if ! on_adhoc; then
			log "associated to another network - clearing record and exiting"
			rm -f "$RESTORE"
			exit 0
		fi
		if ping -c2 -W2 "$HOST" >/dev/null 2>&1; then
			[ $fails -gt 0 ] && log "host answered again after $fails failure(s)"
			fails=0
			continue
		fi
		reason="host unreachable"
	else
		reason="not associated to anything"
	fi

	fails=$((fails + 1))
	log "$reason ($fails/$FAILS_NEEDED)"
	if [ $fails -ge $FAILS_NEEDED ]; then
		log "giving up ($reason) - restoring wifi"
		if restore_wifi; then
			exit 0
		fi
		# A failed attempt is not terminal. Retain the breadcrumb and give the
		# platform time to settle before collecting another failure window.
		fails=0
	fi
done

log "backstop reached after $checks checks - exiting"
