#!/bin/sh

# Clock repair, so HTTPS can work at all.
#
# These handhelds have no battery-backed RTC, so a cold boot starts years in
# the past - an RG SP came up reading 2022-04-20 against a real date of
# 2026-08-18. Every TLS certificate in existence was issued after that, so
# OpenSSL rejects all of them with "certificate is not yet valid" and every
# HTTPS request fails while plain HTTP works perfectly. One wrong clock breaks
# RetroAchievements, update checks, Syncthing and PICO-8 cart downloads at
# once, and every one of them looks like a network fault instead of a clock
# fault - the device resolves DNS, connects, and then refuses the certificate.
#
# On stock Anbernic the vendor's loadapp.sh set the date at boot. BaseOS does
# not use that hook and nothing replaced it, so under BaseOS the clock is never
# set at all.
#
# Deliberately not gated to any platform: a device whose clock is already sane
# returns immediately, so this costs nothing where it is not needed.

# Used only if the floor below cannot be derived from disk. 2025-01-01 UTC.
TIME_SYNC_FALLBACK_FLOOR=1735689600

# Five years past the floor. Beyond that the clock is garbage rather than
# merely unset, and it breaks TLS the same way a past clock does - certificates
# read as expired instead of not-yet-valid. Generous enough that someone still
# running a years-old build with a correct clock is left alone, and the cost of
# being wrong is only an unnecessary sync, which sets the right time anyway.
TIME_SYNC_MAX_AHEAD=157680000

# Run a command with a time limit when the box has timeout(1), plainly when it
# does not. ntpd in particular will sit there indefinitely on a network that
# accepts the packets and never answers.
run_with_time_limit() {
	_limit="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "$_limit" "$@"
	else
		"$@"
	fi
}

file_mtime_epoch() {
	date -r "$1" +%s 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# The earliest time this install could legitimately be running at. Taken from
# the mtime of a file we ship and never rewrite, so it advances by itself with
# every release instead of needing a hardcoded date kept up to date: the clock
# cannot honestly predate the build of the software reading it.
time_sync_floor() {
	_floor="$(file_mtime_epoch /mnt/SDCARD/spruce/spruce)"
	case "$_floor" in
	'' | *[!0-9]*) _floor="$TIME_SYNC_FALLBACK_FLOOR" ;;
	esac
	[ "$_floor" -lt "$TIME_SYNC_FALLBACK_FLOOR" ] && _floor="$TIME_SYNC_FALLBACK_FLOOR"
	echo "$_floor"
}

clock_is_plausible() {
	_now="$(date -u +%s 2>/dev/null)"
	case "$_now" in
	'' | *[!0-9]*) return 1 ;;
	esac
	_floor="$(time_sync_floor)"
	[ "$_now" -ge "$_floor" ] && [ "$_now" -lt $((_floor + TIME_SYNC_MAX_AHEAD)) ]
}

# Convert an RFC 7231 Date header value into the numeric form date(1) accepts
# positionally - MMDDhhmmYYYY.ss - which busybox and coreutils both understand.
# Neither parses the header string itself the same way, so split it by hand.
# Input looks like: Tue, 18 Aug 2026 02:57:48 GMT
http_date_to_stamp() {
	# Word splitting is wanted here: the header is fixed-width and space
	# separated, so the fields land in a known order.
	# shellcheck disable=SC2086
	set -- $1
	[ $# -ge 5 ] || return 1
	_day="$2"
	_mon="$3"
	_year="$4"
	_hms="$5"

	case "$_mon" in
	Jan) _mon=01 ;; Feb) _mon=02 ;; Mar) _mon=03 ;; Apr) _mon=04 ;;
	May) _mon=05 ;; Jun) _mon=06 ;; Jul) _mon=07 ;; Aug) _mon=08 ;;
	Sep) _mon=09 ;; Oct) _mon=10 ;; Nov) _mon=11 ;; Dec) _mon=12 ;;
	*) return 1 ;;
	esac

	_hh="${_hms%%:*}"
	_rest="${_hms#*:}"
	_mm="${_rest%%:*}"
	_ss="${_rest##*:}"

	case "$_day$_year$_hh$_mm$_ss" in
	*[!0-9]* | '') return 1 ;;
	esac
	[ "${#_day}" -eq 2 ] && [ "${#_year}" -eq 4 ] || return 1

	echo "${_mon}${_day}${_hh}${_mm}${_year}.${_ss}"
}

# Headers only. The body is irrelevant - we are here for the Date line, which
# every HTTP response carries.
fetch_http_headers() {
	if command -v curl >/dev/null 2>&1; then
		run_with_time_limit 15 curl -sI --connect-timeout 8 "$1" 2>/dev/null
	elif command -v wget >/dev/null 2>&1; then
		# wget writes the headers to stderr, hence the redirect.
		run_with_time_limit 15 wget -S --spider -q -O /dev/null "$1" 2>&1
	else
		return 1
	fi
}

time_sync_via_ntp() {
	command -v ntpd >/dev/null 2>&1 || return 1
	for _server in pool.ntp.org time.cloudflare.com; do
		run_with_time_limit 20 ntpd -q -n -p "$_server" >/dev/null 2>&1
		if clock_is_plausible; then
			log_message "Time sync: NTP replied from $_server"
			return 0
		fi
	done
	return 1
}

# The fallback that makes this reliable. NTP needs UDP 123, which some networks
# block outright, but we are already talking HTTP - and plain HTTP needs no
# valid clock, which is what breaks the circle: the clock must be right before
# HTTPS works, so the time cannot be fetched over HTTPS.
time_sync_via_http() {
	for _url in http://www.google.com/generate_204 http://detectportal.firefox.com/success.txt; do
		_headers="$(fetch_http_headers "$_url")" || continue
		[ -n "$_headers" ] || continue

		_line="$(echo "$_headers" | grep -i '^date:' | head -n 1)"
		[ -n "$_line" ] || continue

		# Strip the field name and the CR that ends every HTTP header line.
		_value="$(echo "$_line" | sed 's/^[Dd][Aa][Tt][Ee]:[[:space:]]*//; s/\r$//')"
		_stamp="$(http_date_to_stamp "$_value")" || continue

		date -u "$_stamp" >/dev/null 2>&1 || continue
		if clock_is_plausible; then
			log_message "Time sync: took the time from ${_url%%/*}//$(echo "$_url" | cut -d/ -f3) response headers"
			return 0
		fi
	done
	return 1
}

# The user's "Sync Time via Network" setting, from Time Settings in the UI.
#
# Deliberately fails OPEN. A missing file, absent key, unreadable JSON or no jq
# all mean "sync", because the cost of wrongly syncing is a corrected clock,
# while the cost of wrongly skipping is every HTTPS feature silently failing
# with a certificate error - which is the bug this whole file exists to fix.
# Only an explicit false turns it off.
time_sync_is_enabled() {
	_cfg=/mnt/SDCARD/App/PyUI/py-ui-config.json
	[ -f "$_cfg" ] || return 0
	command -v jq >/dev/null 2>&1 || return 0
	# Note: no "// empty" here. jq's alternative operator fires on false as
	# well as null, so it would turn an explicit false into "unset" and the
	# setting could never be switched off. Read the value plainly instead - an
	# absent key prints "null", a broken file prints nothing, and only a real
	# false matches below.
	[ "$(jq -r '.syncTimeViaNetwork' "$_cfg" 2>/dev/null)" = "false" ] && return 1
	return 0
}

# Call once the network is actually up. Cheap and silent on a device whose
# clock is already sane, which is every device with a working RTC.
sync_system_time() {
	if ! time_sync_is_enabled; then
		# Left alone on purpose. Some games read the system clock, so a user
		# may be holding it somewhere deliberately - correcting it behind their
		# back would undo exactly what they set.
		log_message "Time sync: turned off in Time Settings, leaving the clock alone" -v
		return 0
	fi

	if clock_is_plausible; then
		log_message "Time sync: clock already plausible, nothing to do" -v
		return 0
	fi

	log_message "Time sync: clock reads $(date -u), which predates this build - repairing"

	if time_sync_via_ntp || time_sync_via_http; then
		log_message "Time sync: clock set to $(date -u)"
		# Best effort. Most of these devices have no writable RTC, and the
		# ones that do keep it only while charged - the point is the running
		# clock, so a failure here is not worth reporting as an error.
		hwclock -w >/dev/null 2>&1 && log_message "Time sync: persisted to hwclock" -v
		return 0
	fi

	log_message "Time sync: could not determine the time - HTTPS will keep failing with 'certificate is not yet valid'"
	return 1
}
