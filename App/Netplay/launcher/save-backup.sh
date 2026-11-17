#!/bin/sh
# Snapshot this game's persistent saves before an armed emulator opens them.
# Each launch gets one generation, including games that have no save yet.

[ -n "$NETPLAY_SESSION" ] && [ -f "$NETPLAY_SESSION" ] || exit 0
grep -q '^session_save_backups=0$' "$NETPLAY_STATE/settings" 2>/dev/null && exit 0

rom=$1
case "$rom" in
	"$SDCARD_PATH/Roms/"*) rel=${rom#"$SDCARD_PATH/Roms/"} ;;
	/mnt/sdcard/Roms/*) rel=${rom#/mnt/sdcard/Roms/} ;;
	*) exit 0 ;;
esac
system=${rel%%/*}
[ "$system" != "$rel" ] || exit 0
tag=$(printf '%s\n' "$system" | sed -n 's/.*(\([^()]*\))[^()]*$/\1/p')
[ -n "$tag" ] || tag=$system
game=$(basename "$rom")
stem=${game%.*}
backup=$NETPLAY_PAK/backup
mkdir -p "$backup" || exit 1
lock=/tmp/netplay-save-backup.lock
mkdir "$lock" 2>/dev/null || exit 0
stage=$backup/.latest.$$
trap 'rm -rf "$stage"; rmdir "$lock" 2>/dev/null' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$stage" || exit 1

printf 'rom=%s\ndate=%s\n' "$rel" "$(date '+%Y-%m-%d %H:%M:%S')" > "$stage/session.txt"
# NextUI uses Saves/<system>; spruce RetroArch uses Saves/saves and, with
# sort_savefiles_enable, one directory below it for the core.
for system_dir in "$SDCARD_PATH/Saves/$system" "$SDCARD_PATH/Saves/$tag" \
	"$SDCARD_PATH/Saves/saves" "$SDCARD_PATH/Saves/saves"/*; do
	[ -d "$system_dir" ] || continue
	subdir=${system_dir#"$SDCARD_PATH/Saves/"}
	for extension in srm sav dsv rtc eep fla sra mcr mcd; do
		for candidate in "$system_dir/$stem.$extension" "$system_dir/$game.$extension"; do
			[ -f "$candidate" ] || continue
			name=$(basename "$candidate")
			mkdir -p "$stage/$subdir" || exit 1
			cp -p "$candidate" "$stage/$subdir/$name" || exit 1
		done
	done
done

# spruce's standalone DraStic keeps battery saves beside its emulator rather
# than under Saves/. Preserve the game's original .dsv before DS local play.
if [ "$tag" = NDS ] || [ "$system" = NDS ]; then
	system_dir=$SDCARD_PATH/Emu/NDS/backup
	for candidate in "$system_dir/$stem.dsv" "$system_dir/$game.dsv"; do
		[ -f "$candidate" ] || continue
		mkdir -p "$stage/Emu/NDS/backup" || exit 1
		cp -p "$candidate" "$stage/Emu/NDS/backup/$(basename "$candidate")" || exit 1
	done
fi

rm -rf "$backup/previous-2"
[ ! -d "$backup/previous-1" ] || mv "$backup/previous-1" "$backup/previous-2"
[ ! -d "$backup/latest" ] || mv "$backup/latest" "$backup/previous-1"
mv "$stage" "$backup/latest"
