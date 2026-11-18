#!/bin/sh
# changeCmd of Settings > RetroAchievements Settings > Web API Key. Cheevos reads the key
# from KEY_FILE.

KEY_FILE=/mnt/SDCARD/Saves/cheevos/apikey.txt
SPRUCE_CFG=/mnt/SDCARD/Saves/spruce/spruce-config.json
KEY_PATH='.menuOptions."RetroAchievements Settings".webApiKey.selected'
key="$(printf '%s' "$1" | tr -d ' \t\r\n')"

case "$key" in
	"")
		rm -f "$KEY_FILE"
		;;
	*[!A-Za-z0-9]*) ;;
	????????????????????????????????)
		mkdir -p "${KEY_FILE%/*}"
		printf '%s\n' "$key" > "$KEY_FILE"
		;;
esac

# PyUI has already saved what was typed, and reloads the settings after this script. Put the
# key Cheevos will really use in its place, so an entry that isn't a key (a missed or extra
# character on the keyboard) shows as not saved instead of looking saved.
saved="$(tr -d ' \t\r' 2>/dev/null <"$KEY_FILE" | grep -m1 .)"
[ "$saved" = "$1" ] && exit 0
jq --arg key "$saved" "$KEY_PATH = \$key" "$SPRUCE_CFG" >"$SPRUCE_CFG.tmp" &&
	[ -s "$SPRUCE_CFG.tmp" ] && mv -f "$SPRUCE_CFG.tmp" "$SPRUCE_CFG"
rm -f "$SPRUCE_CFG.tmp"
