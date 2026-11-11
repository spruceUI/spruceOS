#!/bin/sh

# Requires globals:
#   PLATFORM
#   EMU_DIR
#   ROM_FILE
#
# Requires functions:
#   log_message, log_and_display_message, start_pyui_message_writer
#   vk_display_preload, emu_log_file, export_sdl_gamecontroller_map
#
# Provides:
#   run_hakux

HAKUX_DATA="/mnt/SDCARD/Saves/spruce/hakux"

# hakuX draws through Vulkan only and loads the driver at run time.
hakux_has_vulkan() {
	for dir in $(echo "$LD_LIBRARY_PATH" | tr ':' ' ') /usr/lib /usr/lib64 /lib \
		/usr/lib/aarch64-linux-gnu /usr/trimui/lib /vendor/lib64; do
		[ -e "$dir/libvulkan.so.1" ] || [ -e "$dir/libvulkan.so" ] && return 0
	done
	return 1
}

hakux_saved() {
	[ -r "$HAKUX_DATA/$1" ] && cat "$HAKUX_DATA/$1"
}

run_hakux() {
	HAKUX_BIN="$EMU_DIR/hakux/hakux.aarch64"

	if ! hakux_has_vulkan; then
		start_pyui_message_writer
		log_and_display_message "Xbox needs a Vulkan graphics driver.\nThis device does not have one."
		sleep 4
		return 1
	fi

	# Settings, shader cache and the emulated hard disk live in the data
	# folder; the emulator reads and writes them relative to where it runs.
	mkdir -p "$HAKUX_DATA/cache" "$HAKUX_DATA/hdd"
	cd "$HAKUX_DATA" || return 1

	# A SquashFS holding one ISO lets an image over 4 GiB sit on FAT32.
	DISC="$ROM_FILE"
	SQFS_MOUNT=""
	case "$ROM_FILE" in
		*.sqfs|*.SQFS)
			SQFS_MOUNT="$(mktemp -d /tmp/hakux-disc.XXXXXX)"
			if ! mount -t squashfs -o loop,ro "$ROM_FILE" "$SQFS_MOUNT"; then
				rmdir "$SQFS_MOUNT"
				start_pyui_message_writer
				log_and_display_message "Could not open $(basename "$ROM_FILE")."
				sleep 4
				return 1
			fi
			DISC="$(find "$SQFS_MOUNT" -maxdepth 1 -type f -iname '*.iso' | head -1)"
			;;
	esac

	# The menu button watchdog owns the Menu button; "Emulator menu" sends SIGUSR2.
	export HAKUX_EXTERNAL_MENU=1
	export HAKUX_NATIVE_BASE="$HAKUX_DATA/cache"
	export HAKUX_SCREENSHOT_DIR="/mnt/SDCARD/Saves/screenshots"
	export NC_TIMEOUT=0
	export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1
	case "$PLATFORM" in
		"SmartPro"|"Brick"|"BrickPro"|"BrickOakMOSS")
			# PowerVR misses depth-EQUAL lighting passes by one step.
			export HAKUX_HLE_QUIRKS="+eq_depth_step"
			export SDL_AUDIODRIVER=alsa
			;;
		"Anbernic"*) export_sdl_gamecontroller_map positional ;;
	esac
	[ -f /opt/inttools/gamecontrollerdb.txt ] && \
		export SDL_GAMECONTROLLERCONFIG_FILE=/opt/inttools/gamecontrollerdb.txt

	# Exit 10: the game asked to relaunch itself (relaunch.bin names the XBE).
	# Exit 20: the settings menu asked for a restart to apply a change.
	rm -f relaunch.bin menu-restart
	RESULT=0
	while :; do
		case "$(hakux_saved render-scale)" in
			0.35|0.5|0.75|1|2|3|4) export HAKUX_RENDER_SCALE="$(hakux_saved render-scale)" ;;
		esac
		NETWORK=off
		[ "$(hakux_saved network-mode)" = "lan" ] && NETWORK=lan

		set -- "$DISC" "hdd=$HAKUX_DATA/hdd" "net=$NETWORK"
		[ "$RESULT" = 10 ] && set -- "$@" relaunch
		rm -f menu-restart

		log_message "hakux_functions.sh: launching $DISC"
		LD_PRELOAD="$(vk_display_preload)" "$HAKUX_BIN" "$@" >> "$(emu_log_file)" 2>&1
		RESULT=$?

		[ "$RESULT" = 10 ] && [ -f relaunch.bin ] && continue
		[ "$RESULT" = 20 ] && [ "$(hakux_saved menu-restart)" = "restart" ] && continue
		break
	done
	sync

	if [ -n "$SQFS_MOUNT" ]; then
		umount "$SQFS_MOUNT" && rmdir "$SQFS_MOUNT"
	fi
}
