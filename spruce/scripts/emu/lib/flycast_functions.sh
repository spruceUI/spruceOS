#!/bin/sh

# Requires globals:
#   ROM_FILE
#   PLATFORM
#   CORE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_flycast_standalone
#   set_ui_scale
#   move_screenshots

set_ui_scale() {

	CFG=/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg

	case "$PLATFORM" in
		"Flip") SCALING=70 ;;
		"Brick") SCALING=120 ;;
		*) SCALING=100 ;;
	esac

	sed "s/^UIScaling[[:space:]]*=[[:space:]]*.*/UIScaling = $SCALING/" "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}

move_screenshots() {
	ss_path="/mnt/SDCARD/Saves/screenshots/$CORE/"
	if [ ! -d "$ss_path" ]; then
		mkdir -p "$ss_path"
	fi

	mv /mnt/SDCARD/Emu/DC/[!dc]*.png "$ss_path" 2>/dev/null
}

run_flycast_standalone() {

	set_ui_scale

	export HOME="/mnt/SDCARD/Emu/DC"
	export XDG_DATA_HOME="/mnt/SDCARD/Emu/DC/data"
	export XDG_CONFIG_HOME="/mnt/SDCARD/Emu/DC/config"
	export LD_LIBRARY_PATH="$HOME/lib64:$LD_LIBRARY_PATH"

	mkdir -p "$HOME/bios"
	mkdir -p "$HOME/data"
	mkdir -p "/mnt/SDCARD/BIOS/dc"
	# -o bind, not --bind: the BaseOS BusyBox mount does not take the long form.
	mount -o bind /mnt/SDCARD/BIOS/dc $HOME/bios
	mount -o bind /mnt/SDCARD/BIOS/dc $HOME/data

	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	# Flycast reads the pad through SDL_GameController when SDL knows a mapping
	# and applies its own standard layout (DC A on SDL A, triggers on the
	# trigger axes). The Flip and the TrimUI line get that from SDL's built-in
	# X360 map; the H700 pad ships no map, so hand it spruce's POSITIONAL one
	# and the same layout follows. Without it flycast sees a raw joystick,
	# looks for mappings/SDL_ANBERNIC-keys.cfg, and finds nothing.
	case "$PLATFORM" in
		"Anbernic"*) export_sdl_gamecontroller_map positional ;;
	esac

	if [ "$CORE" = "Flycast2024-standalone" ]; then
		./flycast2024 "$ROM_FILE" > $(emu_log_file) 2>&1
	else
		./flycast "$ROM_FILE" > $(emu_log_file) 2>&1
	fi

	umount $HOME/bios
	umount $HOME/data

	move_screenshots &
}
