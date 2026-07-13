#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   CORE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_yabasanshiro

run_yabasanshiro() {
	export LD_LIBRARY_PATH=$EMU_DIR/lib64:$LD_LIBRARY_PATH
	export HOME="$EMU_DIR"
	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh
	SATURN_BIOS="/mnt/SDCARD/BIOS/saturn_bios.bin"
	KEYMAP_FILE="/mnt/SDCARD/Emu/SATURN/.yabasanshiro/keymapv2.json"
	YABASANSHIRO="./yabasanshiro"
	case "$PLATFORM" in
		"Flip")
			GUID=030000005e0400008e02000014010000
			;;
		"Brick"|"SmartPro"|"SmartProS")
			GUID=0300a3845e0400008e02000014010000
			;;
		"Pixel2")
			GUID=19008d96010000000221000000010000
			;;
	esac

	[ -n "$GUID" ] && \
	jq --arg guid "$GUID" '.player1.deviceGUID = $guid' "$KEYMAP_FILE" > "${KEYMAP_FILE}.tmp" && mv "${KEYMAP_FILE}.tmp" "$KEYMAP_FILE"

	if [ -f "$SATURN_BIOS" ] && [ "$CORE" = "yabasanshiro-standalone-bios" ]; then
		"$YABASANSHIRO" -r 3 -i "$ROM_FILE" -b "$SATURN_BIOS" > $(emu_log_file) 2>&1
	else
		"$YABASANSHIRO" -r 3 -i "$ROM_FILE" > $(emu_log_file) 2>&1
	fi
}