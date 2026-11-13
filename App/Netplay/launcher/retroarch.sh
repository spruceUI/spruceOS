#!/bin/sh
#
# Not RetroArch. ra-hook.sh bind-mounts this over spruce's RetroArch binary
# (RetroArch/ra64.universal, ra64.h700), the way nextui/minarch.elf stands in for
# MinArch: spruce's launcher runs `<RA_BIN> ... -L <core.so> <rom>`, and for an
# armed session this runs the same command with the shim in the core's place.
#
# The real binary is still reachable at the stash ra-hook.sh bound it to. With
# no session armed, or a core the shim does not drive, that binary is exec'd
# with the arguments we were given, byte for byte.

SDCARD_PATH=/mnt/SDCARD
. "$SDCARD_PATH/App/Netplay/launcher/firmware.sh"
NP="$NETPLAY_PAK"

STASH=/tmp/netplay/ra
REAL_RA="$STASH/$(basename "$0")"
# Anything unexpected -> behave exactly like stock. Without the stash there is
# nothing to run, which only happens if this file is executed by hand.
[ -x "$REAL_RA" ] || { echo "[netplay] no real RetroArch at $REAL_RA" >&2; exit 127; }

# spruce's PLATFORM names the device for spruce's own scripts, and RetroArch's
# children may read it; Netplay's scripts want its build platform. Both are kept
# and each command gets the one it expects.
SPRUCE_PLATFORM="$PLATFORM"
PLATFORM="$(cat "$STASH/platform" 2>/dev/null)"
[ -n "$PLATFORM" ] || exec "$REAL_RA" "$@"

. "$NP/launcher/state-path.sh"
if [ -z "$NETPLAY_SESSION" ] && [ -f "$NETPLAY_STATE/session" ]; then
	NETPLAY_SESSION="$NETPLAY_STATE/session"
	export NETPLAY_SESSION
fi
if [ -z "$NETPLAY_SESSION" ] &&
   [ "$NETPLAY_FORCE_SHIM" != "1" ] &&
   [ ! -f "$NETPLAY_STATE/force-shim" ]; then
	PLATFORM="$SPRUCE_PLATFORM" exec "$REAL_RA" "$@"
fi

# The core and the rom. spruce always passes `-L <core>` before the rom, and the
# rom is the last argument.
CORE=
prev=
for a in "$@"; do
	[ "$prev" = "-L" ] && CORE="$a"
	prev="$a"
	ROM="$a"
done

# The core the session agreed for this system (np_engine_core), from the
# same cores directory as spruce's pick. The shim is still staged under
# spruce's core's filename (SPRUCE_CORE), as for the paired Gambatte, so only
# what loads behind it changes.
SPRUCE_CORE="$CORE"
. "$NP/launcher/core-route.sh"
ENGINE_CORE=$(np_engine_core "$ROM")
if [ -n "$ENGINE_CORE" ] && [ "$ENGINE_CORE" != "$CORE" ]; then
	echo "[netplay] session core $(basename "$ENGINE_CORE" _libretro.so) in place of $(basename "$CORE" _libretro.so)" >&2
	CORE="$ENGINE_CORE"
fi

# Word size. A session paired with a 32-bit device (an A30, which only has
# RetroArch32) carries compat_ra32=1 from core negotiation: this device
# then runs spruce's 32-bit RetroArch with spruce's 32-bit cores and the
# 32-bit shim, so both ends execute the same word size. A device whose
# covered binary already is 32-bit (the A30 itself) just says so.
SHIM_PLATFORM="$PLATFORM"
case "$(basename "$0")" in
	ra32*) SHIM_PLATFORM=my282 ;;
esac
# The Mini Flip runs the A30's armv7 shim and cores; spruce starts its
# RetroArch as RetroArch/retroarch (ra32.mini bound there at boot).
[ "$PLATFORM" = my285 ] && SHIM_PLATFORM=my282
RA32_OVERLAY=
if [ "$SHIM_PLATFORM" != "my282" ] && [ -n "$NETPLAY_SESSION" ] &&
   grep -q '^compat_ra32=1$' "$NETPLAY_SESSION" 2>/dev/null; then
	# The covered binary's own twin first (ra64.h700 -> ra32.h700): the
	# builds differ in more than name - the universal 32-bit build has no
	# fbdev_mali context for the H700's video cfg and dies opening it.
	covered=$(basename "$0")
	for ra32bin in "ra32.${covered#ra64.}" ra32.universal ra32.h700 ra32.mini ra32.a30; do
		if [ -x "$STASH/$ra32bin" ]; then
			REAL_RA="$STASH/$ra32bin"
			SHIM_PLATFORM=my282
			# spruce named the 64-bit core; its 32-bit twin ships beside it.
			case "$CORE" in
				*/cores64/*) CORE="${CORE%/cores64/*}/cores/${CORE##*/}" ;;
			esac
			case "$SPRUCE_CORE" in
				*/cores64/*) SPRUCE_CORE="${SPRUCE_CORE%/cores64/*}/cores/${SPRUCE_CORE##*/}" ;;
			esac
			# spruce layers a per-device 32-bit overlay over the platform
			# cfg when it launches this binary itself (fbdev_mali video
			# context, linuxraw pad). Without it the 32-bit build dies
			# opening its video driver. Its name follows the platform cfg
			# spruce passed us: retroarch-<device>.cfg -> the same name
			# with -32bit in RetroArch/platform/.
			prev=
			for a in "$@"; do
				if [ "$prev" = "--config" ]; then
					cfgname=$(basename "$a" .cfg)
					overlay="$SDCARD_PATH/RetroArch/platform/$cfgname-32bit.cfg"
					[ -f "$overlay" ] && RA32_OVERLAY="$overlay"
				fi
				prev="$a"
			done
			# spruce's 32-bit cores link libstdc++ symbols newer than
			# the 64-bit system's 32-bit runtime (GLIBCXX_3.4.32 vs the
			# 3.4.30 in spruce/<device>/lib32). The cores are the A30
			# builds, and spruce/a30/lib carries the runtime they were
			# built against; it holds no SDL/EGL to shadow lib32's, so
			# it goes first, with lib32 behind it for the rest.
			for lib32 in "$SDCARD_PATH/spruce/a30/lib" "$SDCARD_PATH"/spruce/*/lib32; do
				[ -d "$lib32" ] || continue
				LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$lib32"
				export LD_LIBRARY_PATH
			done
			echo "[netplay] 32-bit peer: running $ra32bin with 32-bit cores" >&2
			break
		fi
	done
fi
if [ "$SHIM_PLATFORM" = "my282" ]; then
	NETPLAY_SHIM_PLATFORM=my282
	export NETPLAY_SHIM_PLATFORM
fi
case "$(basename "$CORE")" in
	fceumm_libretro.so|snes9x_libretro.so|snes9x2005_libretro.so|\
	mednafen_supafaust_libretro.so|picodrive_libretro.so|pcsx_rearmed_libretro.so|\
	gpsp_libretro.so|gambatte_libretro.so|mgba_libretro.so|armgba_libretro.so|\
	genesis_plus_gx_libretro.so|gearsystem_libretro.so) ;;
	*) PLATFORM="$SPRUCE_PLATFORM" exec "$REAL_RA" "$@" ;;
esac

SHIM="$NP/bin/$SHIM_PLATFORM/netplay_shim.so"
if [ ! -f "$SHIM" ]; then
	echo "[netplay] shim missing at $SHIM, launching stock" >&2
	PLATFORM="$SPRUCE_PLATFORM" exec "$REAL_RA" "$@"
fi

# Rejoin the ad hoc network, Wi-Fi power save: as for every NextUI pak.
. "$NP/launcher/pre-launch.sh"

np_route_core "$SPRUCE_CORE" "$CORE"
np_stage_shim || PLATFORM="$SPRUCE_PLATFORM" exec "$REAL_RA" "$@"

# The same command line with the shim as the core.
count=$#
prev=
for a in "$@"; do
	if [ "$prev" = "-L" ]; then set -- "$@" "$SHIM_AS"; else set -- "$@" "$a"; fi
	prev="$a"
done
shift "$count"

# RetroArch's settings for the session (retroarch-session.cfg): no save states,
# rewind, run-ahead or fast-forward, and nothing written back to spruce's config
# on exit. RetroArch keeps one --appendconfig, a |-separated list, so ours joins
# spruce's when it passed one.
SESSION_CFG="$NP/launcher/retroarch-session.cfg"
if [ -f "$SESSION_CFG" ]; then
	# The 32-bit overlay sits between spruce's own appends and the session
	# cfg: platform settings first, then the word-size driver/pad layer,
	# then Netplay's session rules on top.
	extra="$SESSION_CFG"
	[ -n "$RA32_OVERLAY" ] && extra="$RA32_OVERLAY|$SESSION_CFG"
	count=$#
	prev=
	appended=0
	for a in "$@"; do
		if [ "$prev" = "--appendconfig" ]; then
			set -- "$@" "$a|$extra"
			appended=1
		else
			set -- "$@" "$a"
		fi
		prev="$a"
	done
	shift "$count"
	[ "$appended" = 1 ] || set -- --appendconfig "$extra" "$@"
elif [ -n "$RA32_OVERLAY" ]; then
	set -- --appendconfig "$RA32_OVERLAY" "$@"
fi

# Offer the game to the other device; its menu asks the player (invite.sh).
# Detached: the launch does not wait on the network.
sh "$NP/launcher/invite.sh" send "$ROM" "$CORE"

# spruce stops a game by signalling RetroArch by name (this shell carries the
# same name), so pass a stop on rather than dying before RetroArch has saved and
# the shim has put the CPU back.
child=
trap '[ -n "$child" ] && kill -TERM "$child" 2>/dev/null' TERM INT HUP
np_frontend() {
	PLATFORM="$SPRUCE_PLATFORM" "$REAL_RA" "$@" &
	child=$!
	wait "$child"
	rc=$?
	# A trapped signal ends the wait early; RetroArch is still shutting down.
	while kill -0 "$child" 2>/dev/null; do
		wait "$child"
		rc=$?
	done
	child=
	return "$rc"
}

np_run_session "$ROM" "$@"
