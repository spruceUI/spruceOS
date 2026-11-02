#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   CORE
#   LD_LIBRARY_PATH
#   LOG_DIR
#   emu_log_file
#
# Provides:
#   run_drastic

# This is the only "public" function, and is the shared entry point for all devices and DraStic versions
run_drastic() {
	load_drastic_configs
	export HOME="$EMU_DIR"
	cd "$EMU_DIR"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	case "$PLATFORM_FAMILY" in
		"h700")		run_drastic_AnbernicH700 ;;
		"darkmoss") run_drastic_DarkMoss ;;
		"oakmoss")	# a board's own function wins over the shared one (the Brick on oakMOSS runs the Brick's)
			if command -v "run_drastic_$PLATFORM" >/dev/null; then run_drastic_$PLATFORM; else run_drastic_OakMoss; fi ;;
		*)			run_drastic_$PLATFORM  ;; # shell expands this to appropriate real function
	esac
	save_drastic_configs
}

##### SHARED #####

# This is the OG, unmodified DraStic, available on all 64-bit devices.
run_drastic64() {
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
	ready_arch_64_states
	./drastic "$ROM_FILE" > $(emu_log_file) 2>&1
	stash_arch_64_states
}

# $1: the folder with the board family's libadvdrastic.so (default: lib64_A133P_trngaje,
# the TrimUI boards' build). Its libjson-c.so.4 comes from lib64_A133P_trngaje either way.
run_drastic_trngaje_a133p() {
	advdrastic_dir="${1:-$HOME/lib64_A133P_trngaje}"
	ready_arch_64_states
	export LD_LIBRARY_PATH="$HOME/lib64_A133P_trngaje:$LD_LIBRARY_PATH:$HOME/lib64"
	LD_PRELOAD=$advdrastic_dir/libadvdrastic.so ./drastic "$ROM_FILE" > $(emu_log_file) 2>&1
	stash_arch_64_states
}

display_core_unrecognized_for_platform_message() {
	start_pyui_message_writer
	log_and_display_message "NDS $CORE is not recognized for $PLATFORM.\nPlease check your configuration."
	sleep 5
	stop_pyui_message_writer
}


##### A30 #####

# Only Steward version is available on A30. Hardcode this "core" selection.

run_drastic_A30() {
	export CORE="DraStic-Steward"
	ready_arch_32_states
	# the SDL library is hard coded to open ttyS0 for joystick raw input 
	# so we pause joystickinput and create soft link to serial port
	killall -q -STOP joystickinput
	ln -s /dev/ttyS2 /dev/ttyS0
	
	export LD_LIBRARY_PATH="$EMU_DIR"/libs:"$EMU_DIR"/lib32-common:/usr/miyoo/lib:/usr/lib
	export SDL_VIDEODRIVER=mmiyoo
	export SDL_AUDIODRIVER=mmiyoo
	export EGL_VIDEODRIVER=mmiyoo

	./drastic32 "$ROM_FILE"  > $(emu_log_file) 2>&1

	# remove soft link and resume joystickinput
	rm /dev/ttyS0
	killall -q -CONT joystickinput
	stash_arch_32_states
}


##### FLIP #####

run_drastic_Flip(){
	if [ "$CORE" = "DraStic-trngaje" ]; then
		run_drastic_trngaje_Flip

	elif [ "$CORE" = "DraStic-original" ]; then 
		run_drastic64

	else
		display_core_unrecognized_for_platform_message
	fi
}

run_drastic_trngaje_Flip() {
	ready_arch_64_states
	export LD_LIBRARY_PATH="$HOME/lib64_Flip:$LD_LIBRARY_PATH"
	./drastic "$ROM_FILE" > $(emu_log_file) 2>&1
	stash_arch_64_states
}


##### MIYOOMINI #####

# Only Steward version is available on MM family. Hardcode this "core" selection.

run_drastic_MiyooMini() {
	export CORE="DraStic-Steward"

	export HOME="$EMU_DIR"
	export PATH="$EMU_DIR:$PATH"
	export LD_LIBRARY_PATH="$EMU_DIR/libs_MiyooMini:$EMU_DIR/lib32-common:$LD_LIBRARY_PATH"
	export SDL_VIDEODRIVER=mmiyoo
	export SDL_AUDIODRIVER=mmiyoo
	export EGL_VIDEODRIVER=mmiyoo

	cp -f "$EMU_DIR/resources/overlay/grid-empty.png" "$EMU_DIR/resources/overlay/grid.png"

	killall audioserver

	sv=$(cat /proc/sys/vm/swappiness)

	# 60 by default
	echo 10 > /proc/sys/vm/swappiness

	cd "$EMU_DIR"

	set_performance
	log_message "Running DraStic-Steward on MiyooMini"
	ready_arch_32_states
	./drastic32 "$ROM_FILE"
	stash_arch_32_states
	sync
	echo $sv > /proc/sys/vm/swappiness
}

### BRICK / BRICK PRO / SMART PRO S ###

run_drastic_Brick() {
    if [ "$CORE" = "DraStic-original" ]; then
		run_drastic64
	elif [ "$CORE" = "DraStic-trngaje" ]; then
		run_drastic_trngaje_a133p
	else
		display_core_unrecognized_for_platform_message
	fi
}

run_drastic_BrickPro()  { run_drastic_Brick ; }
run_drastic_SmartProS() { run_drastic_Brick ; }

##### SMART PRO #####

run_drastic_SmartPro(){			
	if [ "$CORE" = "DraStic-original" ]; then 
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64_SmartPro_original"
		export SDL_AUDIODRIVER=dsp
		run_drastic64
	elif [ "$CORE" = "DraStic-trngaje" ]; then
		run_drastic_trngaje_a133p
	else
		display_core_unrecognized_for_platform_message
	fi
}


#### Anbernic H700 #####

# H700 only have access to vanilla 64-bit drastic under spruce.
run_drastic_AnbernicH700() { run_drastic64 ; }


##### DARKMOSS #####

# The unmodified 64-bit DraStic. It draws through the system SDL, which already
# turns the picture on the rotated panels (A10 Mini V4, V10, XU Mini M).
run_drastic_DarkMoss() { run_drastic64 ; }


##### OAKMOSS A133P (MagicX Mini Zero 28, Zero 40, XU20 V32; Powkiddy V90S, V20; TrimUI Brick) #####

# Same SoC as the Smart Pro, so the same two DraStic builds apply. Without these
# `run_drastic_$PLATFORM` expanded to an undefined function and nothing launched.
run_drastic_OakMoss() {
	if [ "$CORE" = "DraStic-original" ]; then
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64_SmartPro_original"
		export SDL_AUDIODRIVER=dsp
		run_drastic64
	elif [ "$CORE" = "DraStic-trngaje" ]; then
		# trngaje's newer build (touchscreen through udev); it needs libudev.so.1, which
		# the TrimUI boards have not been checked for, so they keep lib64_A133P_trngaje's.
		run_drastic_trngaje_a133p "$HOME/lib64_oakMOSS_trngaje"
	else
		display_core_unrecognized_for_platform_message
	fi
}

# The TrimUI Brick on oakMOSS runs the stock Brick's builds.
run_drastic_BrickOakMOSS() { run_drastic_Brick ; }


##### PIXEL 2 #####

run_drastic_Pixel2() {
	if [ "$CORE" = "DraStic-trngaje" ]; then
		run_drastic_trngaje_Pixel2
	else
		display_core_unrecognized_for_platform_message
	fi
}

run_drastic_trngaje_Pixel2() {
	ready_arch_64_states
	export LD_LIBRARY_PATH="$HOME/lib64_Pixel2_trngaje:$LD_LIBRARY_PATH"
	./drastic "$ROM_FILE" > $(emu_log_file) 2>&1
	stash_arch_64_states
}


##### CONFIG HANDLING #####

# Configs are set PER-DEVICE, but are currently shared by all variants of DraStic on that device.

load_drastic_configs() {
	CFG_DIR="$EMU_DIR/config"
	RES_DIR="$EMU_DIR/resources"
	cp -f "$(platform_path "$CFG_DIR/drastic-%s.cfg")" "$CFG_DIR/drastic.cfg"
	_steward="$(platform_path "$RES_DIR/settings_%s.json")"
	[ -f "$_steward" ] && cp "$_steward" "$RES_DIR/settings.json"
	sync
}

save_drastic_configs() {
	CFG_DIR="$EMU_DIR/config"
	RES_DIR="$EMU_DIR/resources"
	cp -f "$CFG_DIR/drastic.cfg" "$(platform_path "$CFG_DIR/drastic-%s.cfg")"
	[ -f "$RES_DIR/settings.json" ] && cp "$RES_DIR/settings.json" "$(platform_path "$RES_DIR/settings_%s.json")"
	sync
}

##### SAVE STATE HANDLING #####

# These functions are necessary because save states generated by drastic are not compatible
# across architectures. States recorded on aarch64 can only be properly loaded on aarch64.
# The 32-bit versions are used exclusively with Steward, REGARDLESS of host device's bitness.
# All original and trngaje versions should use the 64-bit states.

# DraStic keeps saves and states in $EMU_DIR/backup; the folder of the arch not
# in use waits as backup-32 / backup-64.
#
# move_drastic_saves FROM TO: rename when TO is absent; otherwise move each entry
# of FROM that TO lacks, never overwriting, and leave FROM holding only the
# conflicts (logged), so nothing is lost either way.
move_drastic_saves() {
	_from="$EMU_DIR/$1"
	_to="$EMU_DIR/$2"
	[ -d "$_from" ] || return 0
	if [ ! -e "$_to" ]; then
		mv "$_from" "$_to"
		return
	fi
	for _f in "$_from"/* "$_from"/.[!.]*; do
		[ -e "$_f" ] || continue
		_name="${_f##*/}"
		if [ "$_name" = ".gitkeep" ]; then
			rm -f "$_f"
		elif [ ! -e "$_to/$_name" ]; then
			mv "$_f" "$_to/"
		else
			log_message "drastic_functions.sh: $1/$_name kept apart, $2 already has one"
		fi
	done
	rmdir "$_from" 2>/dev/null
}

ready_arch_64_states() {
	move_drastic_saves backup-64 backup
}

ready_arch_32_states() {
	move_drastic_saves backup-32 backup
}

stash_arch_64_states() {
	move_drastic_saves backup backup-64
}

stash_arch_32_states() {
	move_drastic_saves backup backup-32
}
