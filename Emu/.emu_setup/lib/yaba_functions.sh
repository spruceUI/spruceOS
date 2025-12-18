#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   CORE
#   LD_LIBRARY_PATH
#
# Provides:
#   run_yabasanshiro

run_yabasanshiro() {
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
	export HOME="$EMU_DIR"
	cd "$HOME"
	SATURN_BIOS="/mnt/SDCARD/BIOS/saturn_bios.bin"
	KEYMAP_FILE="/mnt/SDCARD/Emu/SATURN/.yabasanshiro/keymapv2.json"
	case "$PLATFORM" in
		"Flip")
			YABASANSHIRO="./yabasanshiro" 
			GUID=030000005e0400008e02000014010000
			;;
		"Brick"|"SmartPro"|"SmartProS")
			YABASANSHIRO="./yabasanshiro.trimui" 
			GUID=0300a3845e0400008e02000014010000
			;;
	esac

	[ -n "$GUID" ] && \
	jq --arg guid "$GUID" '.player1.deviceGUID = $guid' "$KEYMAP_FILE" > "${KEYMAP_FILE}.tmp" && mv "${KEYMAP_FILE}.tmp" "$KEYMAP_FILE"

	if [ -f "$SATURN_BIOS" ] && [ "$CORE" = "yabasanshiro-standalone-bios" ]; then
		"$YABASANSHIRO" -r 3 -i "$ROM_FILE" -b "$SATURN_BIOS" > /mnt/SDCARD/Saves/spruce/yabasanshiro-$PLATFORM.log 2>&1
	else
		"$YABASANSHIRO" -r 3 -i "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/yabasanshiro-$PLATFORM.log 2>&1
	fi
}