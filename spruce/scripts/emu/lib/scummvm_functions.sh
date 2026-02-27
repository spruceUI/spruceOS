#!/bin/sh

# Requires globals: EMU_DIR, ROM_FILE, PLATFORM, CORE, LOG_DIR
# Provides: run_scummvm, run_scummvm_menu, prepare_scummvm_bin

prepare_scummvm_bin() {
    case "$PLATFORM" in
        "SmartProS")        SCUMMVM_BIN="$EMU_DIR/scummvm_a523" ;;
        "SmartPro"|"Brick") SCUMMVM_BIN="$EMU_DIR/scummvm_a133p" ;;
        *)                  SCUMMVM_BIN="$EMU_DIR/scummvm" ;;
    esac

    if [ -f "${SCUMMVM_BIN}.7z" ]; then
        /mnt/SDCARD/spruce/bin64/7zr x "${SCUMMVM_BIN}.7z" -o"$EMU_DIR" -y > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            rm -f "${SCUMMVM_BIN}.7z"
            echo "[BIN] New binary extracted and updated." >> "${LOG_DIR}/scummvm-standalone-${PLATFORM}.log"
        fi
    fi
}

run_scummvm_menu() {
	export HOME="/mnt/SDCARD/Saves/"
	cd "$EMU_DIR"

	SCUMMVM_LOG="${LOG_DIR}/scummvm-standalone-${PLATFORM}.log"

	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm/scummvm-${PLATFORM}.ini"
	SAVE_DIR="/mnt/SDCARD/Saves/saves/scummvm-sa"

	if [ ! -d "$SAVE_DIR" ]; then
		mkdir -p "$SAVE_DIR"
	fi

	if [ ! -f "$SCUMMVM_CONFIG" ]; then
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm/scummvm.ini"
		if [ -f "$DEFAULT_CONFIG" ]; then
				DEST_DIR=$(dirname "$SCUMMVM_CONFIG")
			if [ ! -d "$DEST_DIR" ]; then
				mkdir -p "$DEST_DIR"
			fi
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
		export CURL_CA_BUNDLE="$HOME/cacert.pem"
		export SSL_CERT_FILE="$HOME/cacert.pem"
		"$SCUMMVM_BIN" -d10 \
			-c "$SCUMMVM_CONFIG" \
			>> "$SCUMMVM_LOG" 2>&1
	fi
}

run_scummvm() {
	export HOME="$EMU_DIR"
	cd "$EMU_DIR"

	SCUMMVM_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"

	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm/scummvm-${PLATFORM}.ini"
	SCUMMVM_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"
	SAVE_DIR="/mnt/SDCARD/Saves/saves/scummvm-sa"

	if [ ! -d "$SAVE_DIR" ]; then
		mkdir -p "$SAVE_DIR"
	fi

	# Check and copy default config if platform-specific config doesn't exist
	if [ ! -f "$SCUMMVM_CONFIG" ]; then
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm/scummvm.ini"
		if [ -f "$DEFAULT_CONFIG" ]; then
				DEST_DIR=$(dirname "$SCUMMVM_CONFIG")
			if [ ! -d "$DEST_DIR" ]; then
				mkdir -p "$DEST_DIR"
			fi
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