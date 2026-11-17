#!/bin/sh
#
# Game invitations on spruce, between the two devices of a Netplay session.
#
#   invite.sh send ROM CORE                  the RetroArch hook, as a game starts:
#                                            offer it to the other device
#   invite.sh receive SYSTEM ROM CORE NICK   the broker or guest agent, when the
#                                            other device offers one (ROM is the
#                                            path under Roms/, SYSTEM its folder)
#
# An invitation is asked over spruce's game menu, and only there: one that
# arrives during a game, or over an app's own PyUI list, is dropped. The menu
# is paused (SIGSTOP) while Netplay's prompt asks:
#
#   A  Play           queue the game the way PyUI does, then end the menu so
#                     spruce's loop runs it
#   B  Not now        resume the menu where it was, on the screen it left
#   X  Browse SYSTEM  point PyUI's saved position at the game, or the nearest
#                     one this device has, and end the menu: spruce reopens it
#                     there (several seconds: PyUI's own start-up)

. /mnt/SDCARD/App/Netplay/launcher/firmware.sh

ROMS=$SDCARD_PATH/Roms
JQ=$SDCARD_PATH/spruce/bin64/jq
STATE_FILE=$SDCARD_PATH/Saves/pyui-state.json
LOG=$NETPLAY_STATE/invite.log

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# Netplay's build platform: the hook and the broker pass it in; from a shell,
# spruce's own device name is what PLATFORM holds.
netplay_platform() {
	case "$PLATFORM" in
		tg5040|tg5050|h700|my355|my282|my285) echo "$PLATFORM" ;;
		*) . "$SDCARD_PATH/spruce/scripts/helperFunctions.sh" >/dev/null 2>&1
		   np_spruce_platform "$PLATFORM" ;;
	esac
}

send() {
	rom=$1 core=$2
	case "$rom" in
		"$ROMS"/*) rel=${rom#"$ROMS"/} ;;
		/mnt/sdcard/Roms/*) rel=${rom#/mnt/sdcard/Roms/} ;;
		*) return 0 ;;
	esac
	system=${rel%%/*}
	name=$(basename "$core" _libretro.so)
	plat=$(netplay_platform) || return 0
	"$NETPLAY_PAK/bin/$plat/netplay-broker.elf" --invite "$system" "$rel" "$name" \
		>> "$LOG" 2>&1 &
}

# The game this device has that sorts at or after NAME in SYSTEM's folder, else
# the last one: an invited Pokemon Blue with only Red and Yellow here lands on
# Red, beside both.
nearest_rom() {
	dir=$ROMS/$1 name=$2
	[ -f "$dir/$name" ] && { echo "$dir/$name"; return; }
	ls "$dir" 2>/dev/null | grep -v '^\.' | grep -v '^Imgs$' | sort -f |
		awk -v n="$name" '{ last = $0 } tolower($0) >= tolower(n) { print; found = 1; exit }
		                  END { if (!found && last != "") print last }' |
		sed "s#^#$dir/#"
}

# PyUI reads where it was from its state file as it starts.
point_menu_at() {
	label=$1 path=$2
	[ -f "$STATE_FILE" ] || return
	"$JQ" --arg s "$label" --arg g "$path" \
		'.lastMainMenuSelection = "Game" | .lastSystemSelection = $s | .inGameSelectionScreen = true
		 | .[$s].lastGameSelection = $g | .[$s].subfolder = ""' \
		"$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

receive() {
	system=$1 rel=$2 core=$3 nick=$4
	menu=$(pidof MainUI | awk '{print $1}')
	if [ -z "$menu" ]; then log "dropped $rel from $nick: not in spruce's menu"; return 0; fi
	case "$(tr '\0' ' ' < "/proc/$menu/cmdline")" in
		*-optionListFile*|*-msgDisplay*) log "dropped $rel from $nick: an app's menu is up"; return 0 ;;
	esac
	mkdir /tmp/netplay-invite.lock 2>/dev/null || { log "dropped $rel from $nick: already asking"; return 0; }
	trap 'rmdir /tmp/netplay-invite.lock 2>/dev/null' EXIT

	file=$(basename "$rel")
	title=${file%.*}
	rom=$ROMS/$rel
	art=
	for ext in qoi png; do
		[ -f "$ROMS/$system/Imgs/$title.$ext" ] && { art=$ROMS/$system/Imgs/$title.$ext; break; }
	done
	label=$("$JQ" -r '.label // empty' "$SDCARD_PATH/Emu/$system/config.json" 2>/dev/null)
	[ -n "$label" ] || label=$system
	if [ -f "$rom" ]; then accept=PLAY text="$title ($core)"
	else accept= text="$title ($core) - not on this device"
	fi

	pak=$NETPLAY_PAK

	# Drawn by Netplay's PyUI front end in spruce's own theme; netplay.elf
	# holds the pad meanwhile, so the paused menu never sees the answer.
	kill -STOP "$menu"
	# The menu only repaints what changes when it resumes, so give it back
	# the screen it left: every page of the framebuffer, since it may be
	# showing any of them.
	saved_screen=/tmp/netplay-invite.fb
	cat /dev/fb0 > "$saved_screen" 2>/dev/null || rm -f "$saved_screen"
	(cd "$pak" && sh "$pak/launch.sh" --invite --title "$nick invites you to play" --text "$text" \
		${art:+--art "$art"} --accept "$accept" --decline "NOT NOW" --browse "BROWSE $label" \
		--timeout 60) > /dev/null 2>> "$LOG"
	answer=$?
	trap 'rmdir /tmp/netplay-invite.lock 2>/dev/null; rm -f "$saved_screen"' EXIT
	case $answer in
	0)
		log "accepted $rel from $nick"
		point_menu_at "$label" "$rom"
		launcher=$SDCARD_PATH/Emu/$system/$("$JQ" -r '.launch' "$SDCARD_PATH/Emu/$system/config.json")
		escaped=$(printf '%s' "$rom" | sed 's/\([$`"\\]\)/\\\1/g')
		printf 'chmod a+x "%s";"%s" "%s"' "$launcher" "$launcher" "$escaped" > /tmp/cmd_to_run.sh
		kill -9 "$menu"
		;;
	3)
		near=$(nearest_rom "$system" "$file")
		log "browsing $label at ${near:-the start} for $rel from $nick"
		point_menu_at "$label" "${near:-$rom}"
		kill -9 "$menu"
		;;
	*)
		log "declined $rel from $nick ($answer)"
		# No nudge: the restored screen is the repaint, and a press could move
		# the selection (the first one only wakes spruce's screensaver, which
		# the paused time may have brought on).
		[ -s "$saved_screen" ] && cat "$saved_screen" > /dev/fb0 2>/dev/null
		kill -CONT "$menu"
		;;
	esac
}

case "$1" in
	send)    send "$2" "$3" ;;
	receive) receive "$2" "$3" "$4" "$5" ;;
	*) echo "usage: invite.sh send ROM CORE | receive SYSTEM ROM CORE NICK" >&2; exit 2 ;;
esac
