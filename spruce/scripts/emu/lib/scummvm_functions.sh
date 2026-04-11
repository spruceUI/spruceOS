#!/bin/sh

# Requires globals: EMU_DIR, ROM_FILE, PLATFORM, CORE, LOG_DIR
# Provides: run_scummvm, run_scummvm_menu, run_scummvm_scan

# Sets SCUMMVM_BIN, SCUMMVM_CONFIG, DEFAULT_CONFIG based on PLATFORM
_set_scummvm_platform() {
	case "$PLATFORM" in
		"Flip")
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-flip/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-flip/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		"SmartPro")
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-tsp/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-tsp/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		"SmartProS")
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-tsps/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-tsps/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		"Brick")
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-brick/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-brick/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			touch /tmp/trimui_inputd/input_no_dpad /tmp/trimui_inputd/input_dpad_to_joystick
			SCUMMVM_BRICK_JOYSTICK=1
			;;
		"Pixel2")
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-pixel2/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-pixel2/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			enable_digital_to_analog
			;;
		"Anbernic"*)
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-anbernic/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-anbernic/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
		"A30")
			SCUMMVM_BIN="$EMU_DIR/scummvm.a30"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-a30/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-a30/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/liba30:$LD_LIBRARY_PATH"
			export DISPLAY_ROTATION=270
			;;
		"MiyooMini")
			SCUMMVM_BIN="$EMU_DIR/scummvm.mini"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-mini/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-mini/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/libmini:$LD_LIBRARY_PATH"
			;;
		*)
			SCUMMVM_BIN="$EMU_DIR/scummvm.64"
			SCUMMVM_CONFIG="/mnt/SDCARD/Saves/.config/scummvm-flip/scummvm.ini"
			DEFAULT_CONFIG="$EMU_DIR/.config/scummvm-flip/scummvm.ini"
			export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
			;;
	esac

	# Copy default config if user config doesn't exist yet (for all platforms)
	for target in a30 anbernic brick flip mini pixel2 tsp tsps; do
		T_PATH="/mnt/SDCARD/Saves/.config/scummvm-$target/scummvm.ini"
		S_PATH="/mnt/SDCARD/Emu/SCUMMVM/.config/scummvm-$target/scummvm.ini"

		if [ ! -f "$T_PATH" ] && [ -f "$S_PATH" ]; then
			mkdir -p "$(dirname "$T_PATH")"
			cp "$S_PATH" "$T_PATH"
		fi
	done

	SAVE_DIR="/mnt/SDCARD/Saves/saves/scummvm-sa"
	if [ ! -d "$SAVE_DIR" ]; then
		mkdir -p "$SAVE_DIR"
	fi
}

run_scummvm_menu() {
	export HOME="/mnt/SDCARD/Saves/"
	cd "$EMU_DIR"
	# ROM_FILE, CORE not present 
	SCUMMVM_LOG="$(emu_log_file)"
	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	_set_scummvm_platform

	export CURL_CA_BUNDLE="$EMU_DIR/cacert.pem"
	export SSL_CERT_FILE="$EMU_DIR/cacert.pem"
	"$SCUMMVM_BIN" --config="$SCUMMVM_CONFIG" > "$SCUMMVM_LOG" 2>&1
	[ "$SCUMMVM_BRICK_JOYSTICK" = "1" ] && rm -f /tmp/trimui_inputd/input_no_dpad /tmp/trimui_inputd/input_dpad_to_joystick
}

run_scummvm() {
	export HOME="/mnt/SDCARD/Saves/"
	cd "$EMU_DIR"
	SCUMMVM_LOG="$(emu_log_file)"
	export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/gamecontrollerdb.txt"

	_set_scummvm_platform

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

	# Execute ScummVM
	export CURL_CA_BUNDLE="$EMU_DIR/cacert.pem"
	export SSL_CERT_FILE="$EMU_DIR/cacert.pem"
	# Auto-load from autosave slot 0 if a save exists
	SAVE_SLOT_ARG=""
	if [ -f "$SAVE_DIR/$game_id.s00" ]; then
		SAVE_SLOT_ARG="--save-slot=0"
	fi
	"$SCUMMVM_BIN" --config="$SCUMMVM_CONFIG" $SAVE_SLOT_ARG --path="$DATA_PATH" "$game_id" > "$SCUMMVM_LOG" 2>&1
	[ "$SCUMMVM_BRICK_JOYSTICK" = "1" ] && rm -f /tmp/trimui_inputd/input_no_dpad /tmp/trimui_inputd/input_dpad_to_joystick
}

run_scummvm_scan() {
	export HOME="/mnt/SDCARD/Saves/"
	SCAN_LOG="${LOG_DIR}/scummvm-scan.log"
	ROM_DIR="/mnt/SDCARD/Roms/SCUMMVM"

	_set_scummvm_platform

	start_pyui_message_writer
	display_image_and_text "/mnt/SDCARD/Emu/SCUMMVM/scummvm.png" 35 25 "Scanning Games.........." 75

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
	stop_pyui_message_writer
}

sync_game_id() {
	_set_scummvm_platform
	[ ! -f "$SCUMMVM_CONFIG" ] && return
	
	start_pyui_message_writer 2>/dev/null
	display_image_and_text "/mnt/SDCARD/Emu/SCUMMVM/scummvm.png" 35 25 "Syncing Game Database..." 75
	
	local NEW_GAME_DATA=$(awk 'BEGIN {RS="["; FS="\n"} NR>1 { if ($0 ~ /gameid=/ && $0 ~ /path=/) printf "[%s", $0 }' "$SCUMMVM_CONFIG")
	
	for target in a30 anbernic brick flip mini pixel2 tsp tsps; do
		local T_INI="/mnt/SDCARD/Saves/.config/scummvm-$target/scummvm.ini"
		
		if [ -f "$T_INI" ] && [ "$T_INI" != "$SCUMMVM_CONFIG" ]; then
			local TARGET_SYSTEM_ONLY=$(awk 'BEGIN {RS="["; FS="\n"} NR>1 { if (!($0 ~ /gameid=/ && $0 ~ /path=/)) printf "[%s", $0 }' "$T_INI")
			printf "%s\n\n%s" "$TARGET_SYSTEM_ONLY" "$NEW_GAME_DATA" > "$T_INI"
			sed -i '/^$/N;/^\n$/D' "$T_INI"
		fi
	done
	
	sync
	stop_pyui_message_writer 2>/dev/null
}