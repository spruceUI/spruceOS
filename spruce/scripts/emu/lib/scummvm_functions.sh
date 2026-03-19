#!/bin/sh

# Requires globals: EMU_DIR, ROM_FILE, PLATFORM, CORE, LOG_DIR
# Provides: run_scummvm, run_scummvm_menu, run_scummvm_scan

SCUMMVM_DISPLAY_ICON="/mnt/SDCARD/Emu/SCUMMVM/scummvm.png"
SCUMMVM_DISPLAY_WRITER_STARTED=0

scummvm_prepare_display() {
	if pgrep -f "sgDisplayRealtimePort" >/dev/null; then
		SCUMMVM_DISPLAY_WRITER_STARTED=0
		return
	fi

	start_pyui_message_writer
	SCUMMVM_DISPLAY_WRITER_STARTED=1
}

scummvm_teardown_display() {
	if [ "$SCUMMVM_DISPLAY_WRITER_STARTED" -eq 1 ]; then
		stop_pyui_message_writer
		SCUMMVM_DISPLAY_WRITER_STARTED=0
	fi
}

scummvm_display_status() {
	headline="$1"
	detail="$2"

	if [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ]; then
		display_text="Sprucing up your device...\n${headline}"
	else
		display_text="$headline"
	fi

	if [ -n "$detail" ]; then
		display_text="${display_text}\n${detail}"
	fi

	display_image_and_text "$SCUMMVM_DISPLAY_ICON" 35 25 "$display_text" 75
}

run_scummvm_menu() {
	export HOME="/mnt/SDCARD/Saves/"
	cd "$EMU_DIR"

	SCUMMVM_LOG="${LOG_DIR}/scummvm-standalone-${PLATFORM}.log"

	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm/scummvm.ini"
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
		"SmartProS"|"SmartPro"|"Brick"|"Flip")
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		"Pixel2")
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			enable_digital_to_analog
			;;
		*)
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
	esac

	scummvm_prepare_display
	scummvm_display_status "Launching ScummVM" "Opening ScummVM menu..."

	if [ -f "$SCUMMVM_BIN" ]; then
		export CURL_CA_BUNDLE="$EMU_DIR/cacert.pem"
		export SSL_CERT_FILE="$EMU_DIR/cacert.pem"
		"$SCUMMVM_BIN" --config="$SCUMMVM_CONFIG" > "$SCUMMVM_LOG" 2>&1
	fi

	scummvm_teardown_display
}

run_scummvm() {
	export HOME="/mnt/SDCARD/Saves/"
	cd "$EMU_DIR"

	SCUMMVM_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"

	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm/scummvm.ini"
	SCUMMVM_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"
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
		"SmartProS"|"SmartPro"|"Brick"|"Flip")
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		"Pixel2")
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			enable_digital_to_analog
			;;
		*)
			SCUMMVM_BIN="$EMU_DIR/scummvm"
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

		# Use filename as fallback game ID
		game_id=$(cat "$ROM_FILE" | tr -d '\r\n' | xargs)
		[ -z "$game_id" ] && game_id="$romNameNoExt"

		scummvm_prepare_display
		scummvm_display_status "Launching ScummVM" "$romNameNoExt"
		
		# Execute ScummVM
		export CURL_CA_BUNDLE="$EMU_DIR/cacert.pem"
		export SSL_CERT_FILE="$EMU_DIR/cacert.pem"
		"$SCUMMVM_BIN" --config="$SCUMMVM_CONFIG" --path="$DATA_PATH" "$game_id" > "$SCUMMVM_LOG" 2>&1

		scummvm_teardown_display
	fi
}

run_scummvm_scan() {
	export HOME="/mnt/SDCARD/Saves/"

	SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm/scummvm.ini"
	SCAN_LOG="${LOG_DIR}/scummvm-scan.log"
	ROM_DIR="/mnt/SDCARD/Roms/SCUMMVM"

	# For cases where the scan is run for the first time before launching the game or opening the menu.
	if [ ! -f "$SCUMMVM_CONFIG" ]; then
		DEFAULT_CONFIG="$EMU_DIR/.config/scummvm/scummvm.ini"
		if [ -f "$DEFAULT_CONFIG" ]; then
			DEST_DIR=$(dirname "$SCUMMVM_CONFIG")
			[ ! -d "$DEST_DIR" ] && mkdir -p "$DEST_DIR"
			cp "$DEFAULT_CONFIG" "$SCUMMVM_CONFIG"
		fi
	fi

	case "$PLATFORM" in
		"SmartProS"|"SmartPro"|"Brick"|"Flip"|"Pixel2")
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		*)
			SCUMMVM_BIN="$EMU_DIR/scummvm"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
	esac

	scummvm_prepare_display
	scummvm_display_status "Scanning ScummVM" "Checking folders for games..."

    cd "$ROM_DIR" || return 1
    
    for dir in */; do
        [ -d "$dir" ] || continue
        dirName=${dir%/}
        [ "$dirName" = "Imgs" ] && continue 

        targetFile="${dirName}.scummvm"
        full_path="$ROM_DIR/$dirName"

        # [Dual-Check Logic]
        if [ -s "$targetFile" ]; then
            current_id=$(cat "$targetFile" | tr -d '\r\n ' | xargs)
            if grep -q "\[$current_id\]" "$SCUMMVM_CONFIG" 2>/dev/null; then
                echo "SKIP: $targetFile (ID: $current_id) is already registered." >> "$SCAN_LOG"
                continue
            fi
        fi

        echo "Scanning Folder: $dirName" >> "$SCAN_LOG"
        engine_out=$("$SCUMMVM_BIN" --config="$SCUMMVM_CONFIG" --path="$full_path" --add 2>&1 | tee -a "$SCAN_LOG")

        # [Search Stage 1 & 2] Extract primary ID
        game_id=$(echo "$engine_out" | grep "Target:" | awk '{print $2}' | head -n 1)
        if [ -z "$game_id" ]; then
            game_id=$(echo "$engine_out" | sed -n 's/.*Found [^:]*:\([^,]*\), but has already been added.*/\1/p')
        fi

        # [Search Stage 3: The Head Strategy]
        # Use 'head -n 1' to get the cleanest first ID (monkey)
        if [ -n "$game_id" ] || [ -f "$SCUMMVM_CONFIG" ]; then
            # Narrow the range with -B 5, and fish for the topmost pure ID with head -n 1.
            actual_id=$(grep -B 5 "path=$full_path" "$SCUMMVM_CONFIG" | grep "\[" | grep -v "\[scummvm\]" | head -n 1 | tr -d '[]' | tr -d '\r\n ')
            [ -n "$actual_id" ] && game_id="$actual_id"
        fi

        # Final Action: Write CLEAN Game ID to .scummvm file
        if [ -n "$game_id" ]; then
            echo "$game_id" | tr -d '\r\n ' > "$targetFile"
            echo "RESULT: Successfully registered [$game_id] to $targetFile" >> "$SCAN_LOG"
        fi
    done

    sync
    echo "--- ScummVM Smart Scan Completed: $(date) ---" >> "$SCAN_LOG"
	scummvm_teardown_display
}
