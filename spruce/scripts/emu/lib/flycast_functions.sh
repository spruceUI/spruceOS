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
#   build_bios_view
#   migrate_standalone_data
#   share_vmus
#   install_flycast_pad_mapping

# The standalone's own data dir (states, console settings, NAOMI/Atomiswave saves), kept apart from the libretro
# core's files. Its VMU cards are not here: both modules use one card set (share_vmus).
FLYCAST_SA_DATA="${FLYCAST_SA_DATA:-/mnt/SDCARD/Saves/saves/Flycast-standalone}"
FLYCAST_BIOS_SRC="${FLYCAST_BIOS_SRC:-/mnt/SDCARD/BIOS/dc}"
FLYCAST_BIOS_VIEW="${FLYCAST_BIOS_VIEW:-/tmp/flycast-bios}"
FLYCAST_DEFAULTS="${FLYCAST_DEFAULTS:-/mnt/SDCARD/Emu/DC/default_configs}"
# The one card set: the libretro core's cards in BIOS/dc, the only place it keeps them with shared VMUs.
FLYCAST_VMU_DIR="${FLYCAST_VMU_DIR:-/mnt/SDCARD/BIOS/dc}"

set_ui_scale() {

	CFG=/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg

	case "$PLATFORM" in
		"Flip") SCALING=70 ;;
		"Brick"|"BrickOakMOSS") SCALING=120 ;;
		"BrickPro") SCALING=140 ;;
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

# FLYCAST_BIOS_PATH target: links to the BIOS images in BIOS/dc only, so the standalone never reads the libretro
# core's nvmem beside them; the shared cards reach it through Dreamcast.VMUPath alone.
build_bios_view() {
	rm -rf "$FLYCAST_BIOS_VIEW"
	mkdir -p "$FLYCAST_BIOS_VIEW"
	for f in "$FLYCAST_BIOS_SRC"/*; do
		[ -f "$f" ] || continue
		case "${f##*/}" in
			dc_boot.bin|dc_bios.bin|dc_flash.bin|*.zip|*.7z) ln -s "$f" "$FLYCAST_BIOS_VIEW/${f##*/}" ;;
		esac
	done
}

# 0 only when both files are known to hold the same bytes; with no compare tool, both are kept.
vmu_same() {
	if command -v cmp >/dev/null 2>&1; then cmp -s "$1" "$2"; return; fi
	a=$(md5sum < "$1" 2>/dev/null) && b=$(md5sum < "$2" 2>/dev/null) && [ -n "$a" ] && [ "$a" = "$b" ]
}

# Cards the standalone kept in its own folders join the one set, never overwriting or losing a card: the only card
# becomes the shared one, an identical copy is dropped, and a differing one stays beside it as <name>.standalone.bin.
share_vmus() {
	mkdir -p "$FLYCAST_VMU_DIR"
	for port in A1 A2 B1 B2 C1 C2 D1 D2; do
		shared="$FLYCAST_VMU_DIR/vmu_save_$port.bin"
		for card in "$FLYCAST_SA_DATA/flycast/vmu_save_$port.bin" "$FLYCAST_BIOS_SRC/flycast/vmu_save_$port.bin"; do
			[ -f "$card" ] || continue
			if [ ! -e "$shared" ]; then
				mv "$card" "$shared" && log_message "Flycast: $card is now the shared card $shared"
			elif vmu_same "$card" "$shared"; then
				rm -f "$card" && log_message "Flycast: $card equals the shared card $shared, dropped"
			else
				keep="$FLYCAST_VMU_DIR/vmu_save_$port.standalone.bin"
				n=2
				while [ -e "$keep" ]; do
					keep="$FLYCAST_VMU_DIR/vmu_save_$port.standalone-$n.bin"
					n=$((n + 1))
				done
				mv "$card" "$keep" && log_message "Flycast: $card differs from the shared card, kept as $keep"
			fi
		done
	done
}

# One-time move of the standalone's own files from its old data dir (BIOS/dc/flycast, reached through
# a BIOS bind until now) into its save folder; a file already there is never overwritten.
migrate_standalone_data() {
	old="$FLYCAST_BIOS_SRC/flycast"
	new="$FLYCAST_SA_DATA/flycast"
	[ -d "$old" ] || return 0
	mkdir -p "$new"
	for f in "$old"/* "$old"/.[!.]*; do
		[ -e "$f" ] || continue
		[ -e "$new/${f##*/}" ] || mv "$f" "$new/"
	done
	rmdir "$old" 2>/dev/null || true
}

# A board's pad map (UNVERIFIED, generated from its platform cfg's SDL map for the DC controls audit): Flycast v2.7
# drops triggers SDL maps to buttons. Copied only when absent, so a map saved in Flycast's own menu stays.
install_flycast_pad_mapping() {
	for f in "$FLYCAST_DEFAULTS/flycast/pads/$FLYCAST_PAD_MAP"/SDL_*.cfg; do
		[ -f "$f" ] || continue
		dst="${XDG_CONFIG_HOME:-/mnt/SDCARD/Emu/DC/config}/flycast/mappings/${f##*/}"
		[ -e "$dst" ] || { mkdir -p "${dst%/*}" && cp "$f" "$dst"; }
	done
}

run_flycast_standalone() {

	set_ui_scale

	export HOME="/mnt/SDCARD/Emu/DC"
	export XDG_DATA_HOME="$FLYCAST_SA_DATA"
	export FLYCAST_BIOS_PATH="$FLYCAST_BIOS_VIEW"
	export XDG_CONFIG_HOME="/mnt/SDCARD/Emu/DC/config"
	export LD_LIBRARY_PATH="$HOME/lib64:$LD_LIBRARY_PATH"

	mkdir -p "$HOME/bios"
	mkdir -p "$FLYCAST_SA_DATA/flycast"
	mkdir -p "/mnt/SDCARD/BIOS/dc"
	# -o bind, not --bind: the BaseOS BusyBox mount does not take the long form.
	mount -o bind /mnt/SDCARD/BIOS/dc $HOME/bios
	# BIOS/dc on $HOME/data put the libretro core's cards on the standalone's search path, and its
	# first launch moved them away; release a bind an older launch left behind.
	umount "$HOME/data" 2>/dev/null

	share_vmus
	migrate_standalone_data
	build_bios_view

	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	# The Flip and the TrimUI line use the shipped mappings/SDL_Xbox 360 Controller.cfg. A board whose platform
	# cfg names a pad map table (FLYCAST_PAD_MAP) gets spruce's POSITIONAL SDL map and that table's mapping file.
	if [ -n "$FLYCAST_PAD_MAP" ]; then
		export_sdl_gamecontroller_map positional
		install_flycast_pad_mapping
	fi

	# One card set with the libretro core: its folder and no per-game A1 card, as transient settings (-config is
	# not saved to emu.cfg), so an updated card's own emu.cfg can't split the set again.
	if [ "$CORE" = "Flycast2024-standalone" ]; then
		./flycast2024 -config config:Dreamcast.VMUPath="$FLYCAST_VMU_DIR" -config config:PerGameVmu=no "$ROM_FILE" > $(emu_log_file) 2>&1
	else
		./flycast -config config:Dreamcast.VMUPath="$FLYCAST_VMU_DIR" -config config:PerGameVmu=no "$ROM_FILE" > $(emu_log_file) 2>&1
	fi

	umount $HOME/bios

	move_screenshots &
}
