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


# ---------------------------------------------------------------------------
# Automatic timezone
#
# A handheld has no idea where it is, but its public IP does. Once the network
# is up (and the clock is sane, see above) ask a geolocation service for the
# IANA zone name and, if it is one we ship in spruce/zoneinfo, save it to the
# card-global shared-system.json that the UI reads its zone from. PyUI watches
# that file and applies the zone without a restart.
#
# Several providers, tried in order, first valid answer wins. No single host is
# reachable from everywhere (some countries block whole providers), and any of
# these can disappear. Plain-HTTP ones first: they work even if the clock is
# still wrong, HTTPS ones only after sync_system_time has done its job. A
# failure anywhere means "leave the zone alone", never a wrong zone.
#
# Honours the same "Sync Time via Network" toggle as the clock, and the
# timezone mode: "manual" (the user picked a zone in Time Settings) is never
# overwritten. Runs once per boot; a failed attempt may retry on the next
# network-up.
# ---------------------------------------------------------------------------
TZ_SHARED_CONFIG=/mnt/SDCARD/Saves/spruce/shared-system.json
TZ_ZONEINFO_DIR=/mnt/SDCARD/spruce/zoneinfo
TZ_AUTO_DONE_FLAG=/tmp/timezone_auto_done
TZ_PROVIDERS="http://ip-api.com/json/?fields=timezone|json
http://ipwho.is/?fields=timezone.id|jsonid
https://ipapi.co/timezone|text
https://ipinfo.io/timezone|text
http://worldtimeapi.org/api/ip|json"

# auto or manual. A zone saved with no mode recorded predates this feature and
# was picked by hand, so it counts as manual; nothing saved at all is auto.
timezone_mode() {
	command -v jq >/dev/null 2>&1 || { echo auto; return; }
	[ -f "$TZ_SHARED_CONFIG" ] || { echo auto; return; }
	_mode="$(jq -r '.timezoneMode' "$TZ_SHARED_CONFIG" 2>/dev/null)"
	case "$_mode" in
	auto | manual) echo "$_mode"; return ;;
	esac
	_tz="$(jq -r '.timezone' "$TZ_SHARED_CONFIG" 2>/dev/null)"
	case "$_tz" in
	'' | null) echo auto ;;
	*) echo manual ;;
	esac
}

fetch_http_body() {
	if command -v curl >/dev/null 2>&1; then
		run_with_time_limit 20 curl -s --connect-timeout 8 -m 15 "$1" 2>/dev/null
	elif command -v wget >/dev/null 2>&1; then
		run_with_time_limit 20 wget -q -T 15 -O - "$1" 2>/dev/null
	else
		return 1
	fi
}

# Only what could be a zone name we ship: Area/Location[/Sub], safe characters,
# and the file has to exist. Anything else, including error bodies and HTML
# from a captive portal, is rejected.
timezone_is_valid() {
	case "$1" in
	*/*) ;;
	*) return 1 ;;
	esac
	case "$1" in
	*[!A-Za-z0-9_/+-]* | */../* | /* | */) return 1 ;;
	esac
	[ "${#1}" -le 64 ] || return 1
	[ -f "$TZ_ZONEINFO_DIR/$1" ]
}

# $1 = url, $2 = json ("timezone":"X"), jsonid ("timezone":{"id":"X"}) or text
# (the zone on the first line). Prints the zone or fails.
timezone_from_provider() {
	_body="$(fetch_http_body "$1")" || return 1
	[ -n "$_body" ] || return 1
	_body="$(printf '%s' "$_body" | tr -d '\n\r')"
	case "$2" in
	json) _tz="$(printf '%s' "$_body" | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)" ;;
	jsonid) _tz="$(printf '%s' "$_body" | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*{[[:space:]]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)" ;;
	text) _tz="$(printf '%s' "$_body" | head -n 1 | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" ;;
	*) return 1 ;;
	esac
	timezone_is_valid "$_tz" || return 1
	echo "$_tz"
}

sync_timezone_from_network() {
	# First, so the repeat calls (every return to the menu from a game) cost
	# nothing once this boot has an answer.
	[ -f "$TZ_AUTO_DONE_FLAG" ] && return 0
	[ -d "$TZ_ZONEINFO_DIR" ] || return 0
	command -v jq >/dev/null 2>&1 || return 0
	# The Pixel 2 keeps its zone in its own system layer (tz-data.service),
	# which PyUI's shared-config path does not write. Left alone on purpose.
	[ "$PLATFORM" = "Pixel2" ] && return 0
	if ! time_sync_is_enabled; then
		log_message "Timezone: network sync turned off in Time Settings, leaving the zone alone" -v
		return 0
	fi
	if [ "$(timezone_mode)" != "auto" ]; then
		log_message "Timezone: set by hand, leaving it alone" -v
		return 0
	fi

	_found=""
	_old_ifs="$IFS"; IFS='
'
	for _entry in $TZ_PROVIDERS; do
		IFS="$_old_ifs"
		_url="${_entry%%|*}"
		_kind="${_entry##*|}"
		if _found="$(timezone_from_provider "$_url" "$_kind")"; then
			log_message "Timezone: $_found from $(echo "$_url" | cut -d/ -f3)" -v
			break
		fi
		_found=""
	done
	IFS="$_old_ifs"

	if [ -z "$_found" ]; then
		log_message "Timezone: no geolocation provider answered, leaving the zone alone"
		return 1
	fi

	_current=""
	[ -f "$TZ_SHARED_CONFIG" ] && _current="$(jq -r '.timezone // empty' "$TZ_SHARED_CONFIG" 2>/dev/null)"
	if [ "$_current" = "$_found" ]; then
		log_message "Timezone: already $_found" -v
		touch "$TZ_AUTO_DONE_FLAG"
		return 0
	fi

	# Same care PyUI takes writing this file: whole file or nothing.
	_dir="$(dirname "$TZ_SHARED_CONFIG")"
	mkdir -p "$_dir"
	_tmp="$_dir/.shared-system.json.tmp.$$"
	if [ -f "$TZ_SHARED_CONFIG" ]; then
		jq --arg tz "$_found" '.timezone = $tz | .timezoneMode = "auto"' "$TZ_SHARED_CONFIG" > "$_tmp" 2>/dev/null
	else
		jq -n --arg tz "$_found" '{timezone: $tz, timezoneMode: "auto"}' > "$_tmp" 2>/dev/null
	fi
	if [ -s "$_tmp" ] && jq -e . "$_tmp" >/dev/null 2>&1; then
		mv -f "$_tmp" "$TZ_SHARED_CONFIG" && sync
		log_message "Timezone: set to $_found automatically${_current:+ (was $_current)}"
		touch "$TZ_AUTO_DONE_FLAG"
		return 0
	fi
	rm -f "$_tmp"
	log_message "Timezone: could not write $TZ_SHARED_CONFIG"
	return 1
}
