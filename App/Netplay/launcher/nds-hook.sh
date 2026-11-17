#!/bin/sh
# Shadow spruce's AArch64 DS executables without editing Emu/NDS.
. /mnt/SDCARD/App/Netplay/launcher/firmware.sh
dir="$(cd -P "$SDCARD_PATH/Emu/NDS" 2>/dev/null && pwd)" || exit 1
stash=/tmp/netplay/nds
shadow=$NETPLAY_PAK/launcher/nds-shadow.sh
mounted() { awk -v p="$1" '$5 == p { f=1 } END { exit !f }' /proc/self/mountinfo; }
up() {
	[ -f "$shadow" ] || return 1
	mkdir -p "$stash"
	# 4.6.0 calls its AArch64 build drastic; earlier releases used drastic64.
	if [ -x "$dir/drastic" ] && [ -L "$stash/drastic" ]; then
		rm -f "$stash/drastic"
	fi
	for bin in drastic drastic64 dsperate; do
		target=$dir/$bin
		[ -x "$target" ] || continue
		mounted "$target" && continue
		if ! mounted "$stash/$bin"; then
			: > "$stash/$bin"
			mount --bind "$target" "$stash/$bin" || return 1
		fi
		if ! mount --bind "$shadow" "$target"; then
			umount "$stash/$bin" 2>/dev/null
			return 1
		fi
	done
	# The radio hook recognises the basename drastic, not drastic64.
	if [ ! -e "$stash/drastic" ] && [ -e "$stash/drastic64" ]; then
		ln -s drastic64 "$stash/drastic"
	fi
}
down() {
	for bin in drastic drastic64 dsperate; do
		target=$dir/$bin
		mounted "$target" && umount "$target"
		mounted "$stash/$bin" && umount "$stash/$bin"
	done
	rm -f "$stash/drastic" "$stash/drastic64" "$stash/dsperate"
}
case "$1" in up) up ;; down) down ;; *) exit 2 ;; esac
