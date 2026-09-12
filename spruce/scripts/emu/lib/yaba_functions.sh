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
		"Brick"|"BrickPro"|"SmartPro"|"SmartProS")
			GUID=0300a3845e0400008e02000014010000
			;;
		"Pixel2")
			GUID=19008d96010000000221000000010000
			;;
		"Anbernic"*)
			GUID=19000000010000000100000000010000
			seed_xx_yaba_keymap
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
# Anbernic RG XX (H700). yabasanshiro reads the pad as a raw SDL joystick keyed
# by GUID, and every model shares one GUID while the trigger indices differ by
# layout, so the keymap entry is a shipped default per platform
# (Emu/SATURN/xx-pad/keymap-<PLATFORM>.json), merged into keymapv2.json once,
# when the file has no ANBERNIC-keys entry: a bind changed inside the emulator
# stays. Raw indices under the staged mali SDL2: A 3, B 4, Y 5, X 6, L1 7,
# R1 8, SELECT 9, START 10, MENU 11, then L3 12 / L2 13 / R2 14 / R3 15 on
# two-stick models, L2 12 / R2 13 on stickless ones. Same Saturn layout as the
# fleet's X360 entries by position: A on the right button, B on the bottom, C
# on L2, X on the top, Y on the left, Z on R2, L/R on the shoulders. Derived,
# not yet run on the device.
seed_xx_yaba_keymap() {
	key="0_ANBERNIC-keys_19000000010000000100000000010000"
	[ -f "$KEYMAP_FILE" ] || return 0
	if jq -e --arg key "$key" 'has($key) and .player1.deviceName == "ANBERNIC-keys"' "$KEYMAP_FILE" >/dev/null 2>&1; then
		return 0
	fi
	src="$EMU_DIR/xx-pad/keymap-$PLATFORM.json"
	if [ -f "$src" ]; then
		jq --slurpfile seed "$src" '. + $seed[0] | .player1.deviceName = "ANBERNIC-keys"' "$KEYMAP_FILE" > "${KEYMAP_FILE}.tmp" && mv "${KEYMAP_FILE}.tmp" "$KEYMAP_FILE"
	else
		# Fallback only: no shipped entry for this platform. Not reached while
		# Emu/SATURN/xx-pad ships one per platform.
		log_message "xx saturn keymap: no shipped entry for $PLATFORM, generating a fallback from layout ${XX_PAD_LAYOUT:-2stick}"
		generate_xx_yaba_keymap_fallback
	fi
}

# Fallback generator for seed_xx_yaba_keymap - the table the shipped entries
# were rendered from.
generate_xx_yaba_keymap_fallback() {
	case "$XX_PAD_LAYOUT" in
		nostick) l2=12; r2=13 ;;
		*)       l2=13; r2=14 ;;
	esac
	key="0_ANBERNIC-keys_19000000010000000100000000010000"
	jq --arg key "$key" --argjson l2 "$l2" --argjson r2 "$r2" '
	  .[$key] = {
	    "a": {"id": 3, "type": "button", "value": 1},
	    "b": {"id": 4, "type": "button", "value": 1},
	    "c": {"id": $l2, "type": "button", "value": 1},
	    "x": {"id": 6, "type": "button", "value": 1},
	    "y": {"id": 5, "type": "button", "value": 1},
	    "z": {"id": $r2, "type": "button", "value": 1},
	    "l": {"id": 7, "type": "button", "value": 1},
	    "r": {"id": 8, "type": "button", "value": 1},
	    "select": {"id": 9, "type": "button", "value": 1},
	    "start": {"id": 10, "type": "button", "value": 1},
	    "up": {"id": 0, "type": "hat", "value": 1},
	    "right": {"id": 0, "type": "hat", "value": 2},
	    "down": {"id": 0, "type": "hat", "value": 4},
	    "left": {"id": 0, "type": "hat", "value": 8},
	    "analogx": {"id": 0, "type": "axis", "value": 1},
	    "analogy": {"id": 1, "type": "axis", "value": -1}
	  } | .player1.deviceName = "ANBERNIC-keys"' "$KEYMAP_FILE" > "${KEYMAP_FILE}.tmp" && mv "${KEYMAP_FILE}.tmp" "$KEYMAP_FILE"
}
