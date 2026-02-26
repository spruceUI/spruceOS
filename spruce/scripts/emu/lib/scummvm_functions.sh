#!/bin/sh

# Requires globals: EMU_DIR, ROM_FILE, PLATFORM, CORE, LOG_DIR
# Provides: run_scummvm

run_scummvm() {
	export HOME="$EMU_DIR"
	cd "$EMU_DIR"

	SCUMMVM_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"

# ===== [Asset Auto-Install] =====
SEVENZ="/mnt/SDCARD/spruce/bin64/7zr"

if [ -f "scummvm_assets.7z" ]; then
    {
        echo "[$(date)] --- 7z Asset Installation Start ---"
        if "$SEVENZ" x scummvm_assets.7z -y; then
            echo "SUCCESS: Assets extracted. Deleting 7z file."
            rm "scummvm_assets.7z"
        else
            echo "ERROR: 7zr failed to extract assets."
        fi
    } >> "$SCUMMVM_LOG" 2>&1
fi

	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	SCUMMVM_CONFIG="$EMU_DIR/.config/scummvm/scummvm-${PLATFORM}.ini"
	SCUMMVM_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"
	SAVE_DIR="/mnt/SDCARD/Saves/saves/scummvm-sa"

	if [ ! -d "$SAVE_DIR" ]; then
		mkdir -p "$SAVE_DIR"
	fi

	# Check and copy default config if platform-specific config doesn't exist
	if [ ! -f "$SCUMMVM_CONFIG" ]; then
		DEFAULT_CONFIG="$EMU_DIR/.config/scummvm/scummvm.ini"
		if [ -f "$DEFAULT_CONFIG" ]; then
			cp "$DEFAULT_CONFIG" "$SCUMMVM_CONFIG"
		fi
	fi

	case "$PLATFORM" in
		"SmartProS")
			SCUMMVM_BIN="./scummvm_a523"
			export LD_LIBRARY_PATH="$EMU_DIR/lib_a523:$LD_LIBRARY_PATH"
			;;
		"SmartPro"|"Brick")
			SCUMMVM_BIN="./scummvm_a133p"
			export LD_LIBRARY_PATH="$EMU_DIR/lib_a133p:$LD_LIBRARY_PATH"
			;;
		*)
			SCUMMVM_BIN="./scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
	esac

	if [ -f "$SCUMMVM_BIN" ]; then
		# Parse ROM filename
		romName=$(basename "$ROM_FILE")
		romNameNoExt=${romName%.*}
		
		# Correct data path: look for a folder with the same name as the .scummvm file
		DATA_PATH="$(dirname "$ROM_FILE")/$romNameNoExt"
		
		# Fallback to parent directory if folder does not exist
		if [ ! -d "$DATA_PATH" ]; then
			DATA_PATH="$(dirname "$ROM_FILE")"
		fi

		# Extract game ID from file content (if not a .launch file)
		if [ "${romName##*.}" != "launch" ]; then
			game_id=$(cat "$ROM_FILE" | tr -d '\r\n' | xargs)
		fi
		
		# Use filename as fallback game ID
		[ -z "$game_id" ] && game_id="$romNameNoExt"

		# Execute ScummVM
		export CURL_CA_BUNDLE="$HOME/cacert.pem"
		export SSL_CERT_FILE="$HOME/cacert.pem"
		"$SCUMMVM_BIN" -d10 \
			-c "$SCUMMVM_CONFIG" \
			--path="$DATA_PATH" \
			"$game_id" >> "$SCUMMVM_LOG" 2>&1
	fi
}