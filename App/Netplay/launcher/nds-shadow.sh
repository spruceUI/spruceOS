#!/bin/sh
# Entered in place of spruce's drastic, drastic64 or dsperate after stock setup.
. /mnt/SDCARD/App/Netplay/launcher/firmware.sh
NP=$NETPLAY_PAK
bin=$(basename "$0")
real=/tmp/netplay/nds/$bin
[ -x "$real" ] || exit 127
[ -f "$NETPLAY_STATE/session" ] || exec "$real" "$@"
SPRUCE_PLATFORM=$PLATFORM
PLATFORM=$(np_spruce_platform "$SPRUCE_PLATFORM") || exec "$real" "$@"
NETPLAY_SESSION=$NETPLAY_STATE/session
export PLATFORM NETPLAY_SESSION
. "$NP/launcher/pre-launch.sh"
[ -f "$NETPLAY_SESSION" ] || exec "$real" "$@"
role=$(sed -n 's/^role=//p' "$NETPLAY_SESSION" | head -n 1)
peer=$(sed -n 's/^peer=//p' "$NETPLAY_SESSION" | head -n 1)
case "$role" in
	host) ;;
	client) case "$peer" in ''|*[!0-9.]*) exec "$real" "$@" ;; esac ;;
	*) exec "$real" "$@" ;;
esac
rom=$1
case "$rom" in "$SDCARD_PATH/Roms/"*|/mnt/sdcard/Roms/*)
	sh "$NP/launcher/save-backup.sh" "$rom" || :
	sh "$NP/launcher/invite.sh" send "$rom" "$bin" || : ;;
esac
# With Netplay's verbose logs on, mirror the emulator's output into the
# same per-process archive the other spruce launches get (core-route.sh's
# netplay-games layout), which is what check.sh reads afterwards. Nothing
# archived the DS output before, so a spruce DS session left no log at
# all. DSperate's own verbose lines (MP waits, lan pacing) only exist
# with DS_VERBOSE, as on NextUI (cores/dsperate/launch.sh). The emulator
# still runs in the foreground and its exit status is preserved.
np_nds_run() {
	grep -q '^verbose_logs=1$' "$NETPLAY_SESSION" 2>/dev/null || exec "$@"
	command -v tee >/dev/null 2>&1 || exec "$@"
	[ "$bin" = dsperate ] && export DS_VERBOSE=1 DS_LAN_LOG=1
	_game=$(basename "$rom" | sed 's/[^A-Za-z0-9._-]/_/g')
	_sid=$(sed -n 's/^session_id=//p' "$NETPLAY_SESSION" | head -n 1)
	case "$_sid" in *[!0-9A-Fa-f]*|'') _sid=unknown-session ;; esac
	_dir="$NETPLAY_LOGS/netplay-games/${_game:-unknown-game}/$_sid"
	mkdir -p "$_dir" 2>/dev/null || exec "$@"
	_stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null)
	_status="/tmp/netplay-nds-status-$$"
	{ "$@" ; echo $? > "$_status" ; } 2>&1 | tee "$_dir/${_stamp:-unknown-time}-$role-$$.log"
	if [ -f "$_status" ]; then
		read -r _rc < "$_status"
		rm -f "$_status"
		exit "${_rc:-1}"
	fi
	exit 1
}

if [ "$bin" = drastic ] || [ "$bin" = drastic64 ]; then
	radio=$NP/bin/$PLATFORM/libdrastic_wifi.so
	[ -f "$radio" ] || exec "$real" "$@"
	if [ "$role" = host ]; then DRASTIC_WIFI_LAN=host; else DRASTIC_WIFI_LAN=join:$peer; fi
	DRASTIC_WIFI_LAN_NAME=Netplay
	DRASTIC_WIFI_LAN_TIMEOUT_MS=100
	grep -q '^adhoc_ssid=' "$NETPLAY_SESSION" && DRASTIC_WIFI_LAN_TIMEOUT_MS=50
	export DRASTIC_WIFI_LAN DRASTIC_WIFI_LAN_NAME DRASTIC_WIFI_LAN_TIMEOUT_MS
	real=/tmp/netplay/nds/drastic
	LD_PRELOAD="$radio${LD_PRELOAD:+:$LD_PRELOAD}" np_nds_run "$real" "$@"
fi
# Netplay's own DSperate (cores/dsperate/aarch64, built by make
# cores-dsp-spruce): the same build on both devices, with the LAN fixes
# spruce's copy may lack. Only in a session, and only where it runs; a stock
# launch never gets here. spruce's launcher already set the SDL library path
# its own DSperate uses, which this build loads too.
own_dsperate=$NP/cores/dsperate/aarch64/dsperate
if [ -x "$own_dsperate" ] && [ "$(uname -m)" = aarch64 ]; then
	real=$own_dsperate
fi
if [ "$role" = host ]; then set -- "$@" --lan-host Netplay; else set -- "$@" --lan-join "$peer"; fi
DS_LAN_TIMEOUT_MS=100
grep -q '^adhoc_ssid=' "$NETPLAY_SESSION" && DS_LAN_TIMEOUT_MS=50
export DS_LAN_TIMEOUT_MS
set -- "$@" --no-autoload
np_nds_run "$real" "$@"
