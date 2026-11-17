#!/bin/sh
#
# Puts retroarch.sh in front of spruce's RetroArch, writing nothing to spruce.
#
#   ra-hook.sh up       stash each RetroArch binary, then mount the shadow over it
#   ra-hook.sh down     unmount both
#   ra-hook.sh status
#
# The stash is a bind mount of the real binary in /tmp, made before the shadow
# covers it, so the shadow can still run it. Mounts end at reboot, which is also
# when a session ends; the app runs `up` again whenever it arms one.

. /mnt/SDCARD/App/Netplay/launcher/firmware.sh
NP="$NETPLAY_PAK"
# Physical path: mountinfo records it, and on some devices /mnt/SDCARD is a
# symlink to the real mount (/mnt/sdcard on the RG35XXH).
RA_DIR="$(cd -P "$SDCARD_PATH/RetroArch" 2>/dev/null && pwd)" || RA_DIR="$SDCARD_PATH/RetroArch"
STASH=/tmp/netplay/ra
SHADOW="$NP/launcher/retroarch.sh"
BINS="ra64.universal ra64.h700 ra32.universal ra32.h700 ra32.a30 ra32.mini"

log() { echo "[netplay-ra] $*"; }

mounted() {
	awk -v p="$1" '$5 == p { found = 1 } END { exit !found }' /proc/self/mountinfo
}

do_up() {
	[ -n "$PLATFORM" ] || { log "PLATFORM not set"; return 1; }
	[ -f "$SHADOW" ] || { log "missing $SHADOW"; return 1; }
	mkdir -p "$STASH"
	echo "$PLATFORM" > "$STASH/platform"
	n=0
	for bin in $BINS; do
		target="$RA_DIR/$bin"
		[ -f "$target" ] || continue
		if mounted "$target"; then
			# Already covered - but by the shadow as it was when first
			# bound. An updated pak replaces that file without touching
			# this mount, and a fresh bind will not stack over the old
			# one here, so uncover and fall through to cover it with
			# the current shadow. Safe at arm time: nothing launches
			# between the two mounts.
			umount "$target" 2>/dev/null || { log "cannot uncover $bin"; n=$((n + 1)); continue; }
		fi
		[ -f "$STASH/$bin" ] || : > "$STASH/$bin"
		if ! mounted "$STASH/$bin"; then
			mount --bind "$target" "$STASH/$bin" || { log "cannot stash $bin"; return 1; }
		fi
		if ! mount --bind "$SHADOW" "$target"; then
			umount "$STASH/$bin" 2>/dev/null
			log "cannot cover $bin"
			return 1
		fi
		log "covered $bin"
		n=$((n + 1))
	done
	[ "$n" -gt 0 ] || { log "no RetroArch binary in $RA_DIR"; return 1; }
	mini_up
}

# The Mini Flip starts RetroArch as RetroArch/retroarch, a placeholder spruce
# binds ra32.mini onto at boot - so covering ra32.mini (above) does not reach
# it. Stash the real ra32.mini under that name and cover the placeholder; down
# puts spruce's bind back.
mini_up() {
	target="$RA_DIR/retroarch"
	[ -f "$RA_DIR/ra32.mini" ] && [ -f "$target" ] || return 0
	[ -f "$STASH/ra32.mini" ] && mounted "$STASH/ra32.mini" || return 0
	if ! mounted "$target" && [ ! -f "$STASH/retroarch.spruce" ]; then
		return 0   # not a Mini boot: spruce never bound anything here
	fi
	: > "$STASH/retroarch.spruce"
	while mounted "$target"; do umount "$target" 2>/dev/null || { log "cannot uncover retroarch"; return 1; }; done
	[ -f "$STASH/retroarch" ] || : > "$STASH/retroarch"
	mounted "$STASH/retroarch" || mount --bind "$STASH/ra32.mini" "$STASH/retroarch" ||
		{ log "cannot stash retroarch"; return 1; }
	mount --bind "$SHADOW" "$target" || { log "cannot cover retroarch"; return 1; }
	log "covered retroarch (ra32.mini)"
}

mini_down() {
	[ -f "$STASH/retroarch.spruce" ] || return 0
	target="$RA_DIR/retroarch"
	while mounted "$target"; do umount "$target" 2>/dev/null || break; done
	mounted "$STASH/retroarch" && umount "$STASH/retroarch"
	rm -f "$STASH/retroarch" "$STASH/retroarch.spruce"
	mount --bind "$RA_DIR/ra32.mini" "$target"   # as spruce's boot left it
}

do_down() {
	for bin in $BINS; do
		target="$RA_DIR/$bin"
		mounted "$target" && umount "$target"
		mounted "$STASH/$bin" && umount "$STASH/$bin"
		rm -f "$STASH/$bin"
	done
	rm -f "$STASH/platform"
	mini_down   # last: ra32.mini must be uncovered before it is bound back
	return 0
}

do_status() {
	for bin in $BINS; do
		[ -f "$RA_DIR/$bin" ] || continue
		if mounted "$RA_DIR/$bin"; then echo "covered  $bin"; else echo "stock    $bin"; fi
	done
	[ -f "$STASH/retroarch.spruce" ] && echo "covered  retroarch"
}

case "$1" in
	up)     do_up ;;
	down)   do_down ;;
	status) do_status ;;
	*) echo "usage: ra-hook.sh up|down|status" >&2; exit 2 ;;
esac
