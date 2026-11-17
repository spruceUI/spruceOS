#!/bin/sh
#
# Which core an armed game really runs, and how the frontend is run around it.
# Sourced by each firmware's frontend shadow - nextui/minarch.elf in place of
# MinArch, spruce/retroarch.sh in place of RetroArch - which own only how their
# frontend is found and invoked. Everything a session decides about cores lives
# here, so the two firmwares cannot make different choices for the same session.
#
# The caller sets NP, PLATFORM, NETPLAY_SESSION (empty when unarmed) and defines
#
#   np_frontend <args...>   run the real frontend with the core at $SHIM_AS
#
# then calls np_route_core <requested core path>, np_stage_shim, and
# np_run_session <rom path> <args...>, whose status it exits with.

# The core the session agreed for a ROM's system (app/engines.c decides; the
# app writes engine_core.<SYS>=<path> for this device into the session), or
# nothing: no agreement, or a peer that predates engines, leaves the
# firmware's own core. The system comes from the ROM's folder: spruce names
# it Roms/<TAG>, NextUI Roms/<Name> (<TAG>).
np_engine_core() {
	[ -n "$NETPLAY_SESSION" ] || return 0
	case "$1" in */Roms/*) ;; *) return 0 ;; esac
	_folder=${1#*/Roms/}
	_folder=${_folder%%/*}
	_sys=$(printf '%s\n' "$_folder" | sed -n 's/.*(\([^()]*\))[^()]*$/\1/p')
	[ -n "$_sys" ] || _sys=$_folder
	case "$_sys" in
		SMS) _sys=MS ;; THIRTYTWOX) _sys=32X ;; SUPA) _sys=SFC ;; MGBA) _sys=GBA ;;
	esac
	_core=$(sed -n "s/^engine_core\.$_sys=//p" "$NETPLAY_SESSION" 2>/dev/null | head -n 1)
	[ -n "$_core" ] && [ -f "$_core" ] && echo "$_core"
	return 0
}

# The shim has to be loaded under the real core's filename. MinArch derives
# core.name from basename(path) truncated at the last underscore, and core.name
# feeds config_dir and states_dir; spruce maps the same basename to its save
# folder. Load it as anything else and the user's save states move. Copying per
# core name is what keeps those paths identical.
#
# An optional second argument is the core to run in place of the requested one
# (the session's engine, np_engine_core). The shim keeps the requested core's
# filename; everything decided about the core follows the one that runs.
np_route_core() {
	CORE="$1"
	CORE_NAME="$(basename "$CORE")"

	# Installed cores remain first choice. The setup app writes a per-core
	# selection only after both devices compare their installed builds and agree
	# that the same packaged compatibility build is available locally on each.
	RUN_CORE="${2:-$CORE}"
	REAL_CORE="$RUN_CORE"
	RUN_NAME="$(basename "$RUN_CORE")"
	CORE_ID="${RUN_NAME%_libretro.so}"
	# Word size of the frontend that will load the core. Normally the
	# platform's own; a 64-bit spruce device that negotiated down for a
	# 32-bit peer (compat_ra32) runs its 32-bit RetroArch instead, and
	# the caller says so with NETPLAY_SHIM_PLATFORM=my282.
	case "${NETPLAY_SHIM_PLATFORM:-$PLATFORM}" in
		my282|my285) COMPAT_ARCH=armv7 ;;
		*)     COMPAT_ARCH=aarch64 ;;
	esac
	COMPAT_CORE="$NP/cores/compatibility/$COMPAT_ARCH/$RUN_NAME"
	# The A30's stock SFC pak asks for Snes9x 2005. Compatibility negotiation
	# marks that requested identity, but deliberately routes it to the portable
	# Supafaust artifact shared with the other platforms under the canonical
	# snes9x filename.
	if [ "$CORE_ID" = "snes9x2005" ]; then
		COMPAT_CORE="$NP/cores/compatibility/$COMPAT_ARCH/snes9x_libretro.so"
	fi
	# Packaged cores are per word size too: under compat_ra32 the frontend
	# loading them is the 32-bit one, so route to the my282 builds.
	NETPLAY_CORE="$NP/cores/override/${NETPLAY_SHIM_PLATFORM:-$PLATFORM}/$RUN_NAME"
	DUAL_GAMBATTE_CORE="$NP/cores/override/${NETPLAY_SHIM_PLATFORM:-$PLATFORM}/gambatte_dual_libretro.so"
	DUAL_MGBA_CORE="$NP/cores/override/${NETPLAY_SHIM_PLATFORM:-$PLATFORM}/mgba_dual_libretro.so"
	CORE_NOTICE=""

	# The stock gambatte has Game Link compiled out and stock gpSP lacks this
	# pak's RFU fixes. During an armed session these two packaged builds are the
	# implementation, not merely a version fallback - so they get their own
	# notice ("net-enabled core"), distinct from the compatibility artifact that
	# is only ever selected because two devices' installed builds disagree.
	#
	# NETPLAY_SERIAL_FALLBACK names the file the shim writes when a pairing turns
	# out not to be hostable on both devices. It is created *by that process*,
	# so a stale one from a crash must not silently demote the next launch: the
	# retry in np_run_session removes it before every attempt.
	SERIAL_FALLBACK_MARKER="/tmp/netplay-serial-fallback.$$"
	case "$CORE_ID" in
		gambatte)
			# GB/GBC link sessions use the paired core: both consoles and the
			# serial cable stay in-process, while the shim exchanges only inputs.
			# Linked cartridges may differ, but each device must own both of them;
			# when the shim finds it cannot, it asks for the relaunch handled in
			# np_run_session. If the paired artifact is absent, retain the
			# network-link core.
			if [ -n "$NETPLAY_SESSION" ] &&
			   [ "$NETPLAY_DUAL_DISABLE" != "1" ] &&
			   grep -q '^instanced_gambatte=1$' "$NETPLAY_SESSION" 2>/dev/null &&
			   [ -f "$DUAL_GAMBATTE_CORE" ]; then
				REAL_CORE="$DUAL_GAMBATTE_CORE"
				NETPLAY_DUAL_CORE=1
				NETPLAY_SERIAL_FALLBACK="$SERIAL_FALLBACK_MARKER"
				export NETPLAY_DUAL_CORE NETPLAY_SERIAL_FALLBACK
				CORE_NOTICE=paired
			elif [ -f "$NETPLAY_CORE" ]; then
				REAL_CORE="$NETPLAY_CORE"
				NETPLAY_COMPAT_CORE=1
				export NETPLAY_COMPAT_CORE
				CORE_NOTICE=netlink
			fi
			;;
		gpsp)
			if [ -f "$NETPLAY_CORE" ]; then
				REAL_CORE="$NETPLAY_CORE"
				NETPLAY_COMPAT_CORE=1
				export NETPLAY_COMPAT_CORE
				CORE_NOTICE=netlink
			fi
			;;
		mgba)
			if [ -n "$NETPLAY_SESSION" ] &&
			   [ "$NETPLAY_DUAL_DISABLE" != "1" ] &&
			   grep -q '^instanced_mgba=1$' "$NETPLAY_SESSION" 2>/dev/null &&
			   [ -f "$DUAL_MGBA_CORE" ]; then
				REAL_CORE="$DUAL_MGBA_CORE"
				NETPLAY_DUAL_CORE=1
				export NETPLAY_DUAL_CORE
				CORE_NOTICE=paired
			fi
			;;
		armgba)
			# armGBA's own Link Mode option picks the shim's path:
			# Separate carries its cable over netpacket, Together
			# shares inputs. The frontend's option file is settled
			# before the core loads, so read it here; the shim falls
			# back to the frontend variable, then to Separate.
			if [ -z "$NETPLAY_ARMGBA_LINK_MODE" ]; then
				for _opt in \
					"$SDCARD_PATH/RetroArch/.retroarch/config/armGBA/armGBA.opt" \
					"$SDCARD_PATH/RetroArch/.retroarch/retroarch-core-options.cfg"; do
					[ -f "$_opt" ] || continue
					NETPLAY_ARMGBA_LINK_MODE="$(sed -n 's/^armgba_link_mode *= *"\(.*\)".*/\1/p' "$_opt" | head -n 1)"
					[ -n "$NETPLAY_ARMGBA_LINK_MODE" ] && break
				done
				[ -n "$NETPLAY_ARMGBA_LINK_MODE" ] && export NETPLAY_ARMGBA_LINK_MODE
			fi
			;;
	esac
	if [ "$NETPLAY_DUAL_CORE" != "1" ] && [ -n "$NETPLAY_SESSION" ] &&
	   grep -q "^compat_core\.$CORE_ID=1$" "$NETPLAY_SESSION" 2>/dev/null &&
	   [ -f "$COMPAT_CORE" ]; then
		REAL_CORE="$COMPAT_CORE"
		NETPLAY_COMPAT_CORE=1
		export NETPLAY_COMPAT_CORE
		CORE_NOTICE=compatibility
		echo "[netplay] installed cores differ; using compatibility core for $RUN_NAME" >&2
	fi

	# If negotiation found no common fallback (including when the option is
	# off), retain the installed core but tell the player that determinism is
	# no longer assured. A selected compatibility artifact missing at launch is
	# treated the same way: it is unexpected, but warning and continuing is the
	# requested UX.
	#
	# The paired core is chosen for what it is, not because two builds
	# disagreed, so a compatibility verdict about the ordinary gambatte must not
	# relabel it.
	if [ "$NETPLAY_DUAL_CORE" != "1" ] && [ -n "$NETPLAY_SESSION" ] &&
	   grep -q "^compat_core\.$CORE_ID=1$" "$NETPLAY_SESSION" 2>/dev/null &&
	   [ ! -f "$COMPAT_CORE" ]; then
		CORE_NOTICE=mismatch
		echo "[netplay] selected compatibility core missing; using installed core" >&2
	elif [ -z "$CORE_NOTICE" ] && [ -n "$NETPLAY_SESSION" ] &&
	     grep -q "^core_mismatch\.$CORE_ID=1$" "$NETPLAY_SESSION" 2>/dev/null; then
		CORE_NOTICE=mismatch
	fi

	if [ -n "$CORE_NOTICE" ]; then
		NETPLAY_CORE_NOTICE="$CORE_NOTICE"
		export NETPLAY_CORE_NOTICE
	fi
	NETPLAY_REAL_CORE="$REAL_CORE"
	export NETPLAY_REAL_CORE
}

# Puts the shim at $SHIM_AS. Fails, leaving the caller to launch stock, when it
# cannot be staged.
np_stage_shim() {
	SHIM_DIR="$NP/cores"
	SHIM_AS="$SHIM_DIR/$CORE_NAME"
	mkdir -p "$SHIM_DIR"
	if [ ! -f "$SHIM_AS" ] || ! cmp -s "$SHIM" "$SHIM_AS"; then
		# Write beside the destination and rename, so a power loss or
		# overlapping launch can never leave the frontend loading a partially
		# copied shared object.
		SHIM_TMP="$SHIM_AS.tmp.$$"
		if ! cp "$SHIM" "$SHIM_TMP" || ! mv -f "$SHIM_TMP" "$SHIM_AS"; then
			rm -f "$SHIM_TMP"
			echo "[netplay] could not stage shim as $SHIM_AS, launching stock" >&2
			return 1
		fi
	fi
}

# The firmware's ordinary per-system log is truncated by every launch. In
# verbose mode, mirror the complete emulator process output into an immutable
# file so a crash is not erased by the rejoin attempt that follows it. Launches
# are grouped by game and session id, but never appended to one ambiguous
# stream: each process gets its own timestamp/role/pid file. A demotion relaunch
# is a second process and gets its own file for the same reason.
np_run_frontend() {
	ROM_PATH="$1"
	shift
	if [ "$VERBOSE_LOGS" = "1" ]; then
		GAME_NAME="$(basename "$ROM_PATH")"
		SAFE_GAME="$(printf '%s' "$GAME_NAME" | sed 's/[^A-Za-z0-9._-]/_/g')"
		[ -n "$SAFE_GAME" ] || SAFE_GAME=unknown-game
		SESSION_ID="$(sed -n 's/^session_id=//p' "$NETPLAY_SESSION" | head -n 1)"
		ROLE="$(sed -n 's/^role=//p' "$NETPLAY_SESSION" | head -n 1)"
		case "$SESSION_ID" in *[!0-9A-Fa-f]*|'') SESSION_ID=unknown-session ;; esac
		case "$ROLE" in host|client) ;; *) ROLE=unknown ;; esac
		LOG_DIR="$NETPLAY_LOGS/netplay-games/$SAFE_GAME/$SESSION_ID"
		STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null)"
		[ -n "$STAMP" ] || STAMP=unknown-time
		LOG_BASENAME="$LOG_DIR/$STAMP-$ROLE-$$"
		ARCHIVE_LOG="$LOG_BASENAME.log"
		LOG_SEQUENCE=1
		while [ -e "$ARCHIVE_LOG" ]; do
			ARCHIVE_LOG="$LOG_BASENAME-$LOG_SEQUENCE.log"
			LOG_SEQUENCE=$((LOG_SEQUENCE + 1))
		done
		STATUS_FILE="/tmp/netplay-frontend-status-$$"
		if mkdir -p "$LOG_DIR" 2>/dev/null; then
			{
				echo "=== Netplay game process ==="
				echo "time=$STAMP platform=$PLATFORM role=$ROLE session=$SESSION_ID pid=$$"
				echo "rom=$ROM_PATH"
				echo "requested_core=$CORE"
				echo "real_core=$REAL_CORE"
				np_frontend "$@"
				rc=$?
				echo "=== process exited status=$rc ==="
				printf '%s\n' "$rc" > "$STATUS_FILE"
			} 2>&1 | tee "$ARCHIVE_LOG"
			if [ -f "$STATUS_FILE" ]; then
				read rc < "$STATUS_FILE"
				rm -f "$STATUS_FILE"
			else
				rc=1
			fi
			return "$rc"
		fi
	fi
	np_frontend "$@"
}

# The shim pins the CPU governor for the session and records what it replaced
# in this file. A clean exit restores it and removes the file; after a crash
# the file is still here, and this is the only thing left to put it back.
# That is why an armed session never execs the frontend: this shell outlives it.
CPU_RECORD=/tmp/netplay-cpu-restore
np_cpu_restore_after_crash() {
	[ -f "$CPU_RECORD" ] || return 0
	while read -r dir gov min; do
		case "$dir" in */cpufreq) ;; *) continue ;; esac
		[ -n "$gov" ] && echo "$gov" > "$dir/scaling_governor" 2>/dev/null
		[ -n "$min" ] && echo "$min" > "$dir/scaling_min_freq" 2>/dev/null
	done < "$CPU_RECORD"
	rm -f "$CPU_RECORD"
	echo "[netplay] restored CPU scaling after an unclean exit" >&2
}

np_run_session() {
	# This happens once per game launch, before the first frontend attempt. A
	# paired-core fallback must not overwrite the original snapshot.
	if [ -n "$NETPLAY_SESSION" ] && [ -f "$NP/launcher/save-backup.sh" ]; then
		sh "$NP/launcher/save-backup.sh" "$1" ||
			echo "[netplay] could not back up original save for $1" >&2
	fi
	: "${NETPLAY_LOGS:=${USERDATA_PATH:-$SDCARD_PATH/.userdata/$PLATFORM}/logs}"
	VERBOSE_LOGS=0
	if [ -n "$NETPLAY_SESSION" ] &&
	   grep -q '^verbose_logs=1$' "$NETPLAY_SESSION" 2>/dev/null &&
	   command -v tee >/dev/null 2>&1; then
		VERBOSE_LOGS=1
	fi
	rm -f "$CPU_RECORD"

	if [ "$NETPLAY_DUAL_CORE" != "1" ]; then
		np_run_frontend "$@"
		rc=$?
		np_cpu_restore_after_crash
		return "$rc"
	fi

	# Instanced link needs both devices to own both cartridges, and neither
	# device can know that until two running games have compared notes. The
	# paired core has no network Game Link of its own - it owns the cable
	# between its own two consoles - so a pairing that cannot be hosted here has
	# to become a different process running the net-enabled core. The shim
	# writes the marker and asks the frontend to shut down; we relaunch once,
	# with instancing off.
	#
	# Once, deliberately. The second attempt cannot ask for a third, so a bug in
	# the negotiation costs a reload rather than an unbreakable loop.
	rm -f "$SERIAL_FALLBACK_MARKER"
	np_run_frontend "$@"
	rc=$?
	if [ -f "$SERIAL_FALLBACK_MARKER" ]; then
		REASON="$(cat "$SERIAL_FALLBACK_MARKER" 2>/dev/null)"
		rm -f "$SERIAL_FALLBACK_MARKER"
		if [ -f "$NETPLAY_CORE" ]; then REAL_CORE="$NETPLAY_CORE"; else REAL_CORE="$RUN_CORE"; fi
		echo "[netplay] instanced link declined (reason=$REASON); relaunching $RUN_NAME on network serial" >&2
		NETPLAY_REAL_CORE="$REAL_CORE"
		NETPLAY_DUAL_DISABLE=1
		NETPLAY_CORE_NOTICE=serial-fallback
		NETPLAY_DUAL_CORE=
		unset NETPLAY_SERIAL_FALLBACK
		export NETPLAY_REAL_CORE NETPLAY_DUAL_DISABLE NETPLAY_CORE_NOTICE NETPLAY_DUAL_CORE
		np_run_frontend "$@"
		rc=$?
	fi
	np_cpu_restore_after_crash
	return "$rc"
}
