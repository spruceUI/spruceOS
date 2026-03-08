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
#   run_drastic


run_drastic() {
	load_drastic_configs

	#Why do we use grid on NDS but no other systems?
	cp -f $nds_emu_dir/resources/overlay/grid-enabled.png $nds_emu_dir/resources/overlay/grid.png

	export HOME=$EMU_DIR
	cd $EMU_DIR
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	
	# shell expands this to appropriate real function
	run_drastic_$PLATFORM

	sync
	save_drastic_configs
}

##### SHARED #####

run_drastic64() {
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
	ready_arch_64_states
	pin_to_dedicated_cores drastic64 2
	./drastic64 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	stash_arch_64_states
}

run_drastic_trngaje_a133p() {
	ready_arch_64_states
	export LD_LIBRARY_PATH="$HOME/lib64_A133P_trngaje:$LD_LIBRARY_PATH:$HOME/lib64"
	[ ! -e ./drastic ] && cp ./drastic64 ./drastic
	./drastic "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
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
	
	export LD_LIBRARY_PATH=libs:/usr/miyoo/lib:/usr/lib
	export SDL_VIDEODRIVER=mmiyoo
	export SDL_AUDIODRIVER=mmiyoo
	export EGL_VIDEODRIVER=mmiyoo

	pin_to_dedicated_cores drastic32 2
	./drastic32 "$ROM_FILE"  > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

	# remove soft link and resume joystickinput
	rm /dev/ttyS0
	killall -q -CONT joystickinput
	stash_arch_32_states
}


##### FLIP #####

run_drastic_Flip(){
	if [ "$CORE" = "DraStic-Steward" ]; then
		if [ -d /usr/l32 ]; then
			run_drastic_steward_Flip
		else
			display_bad_flip_firmware_message
		fi

	elif [ "$CORE" = "DraStic-trngaje" ]; then
		run_drastic_trngaje_Flip

	elif [ "$CORE" = "DraStic-original" ]; then 
		run_drastic64

	else
		display_core_unrecognized_for_platform_message
	fi
}

run_drastic_steward_Flip() {
	ready_arch_32_states
	export SDL_VIDEODRIVER=NDS
	export LD_LIBRARY_PATH="$HOME/lib32_Flip:/usr/lib32:$LD_LIBRARY_PATH"
	./drastic32 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	stash_arch_32_states
}

run_drastic_trngaje_Flip() {
	ready_arch_64_states
	export LD_LIBRARY_PATH="$HOME/lib64_Flip:$LD_LIBRARY_PATH"
	[ ! -e ./drastic ] && cp ./drastic64 ./drastic
	./drastic "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	stash_arch_64_states
}

# some miyoo flip firmware versions have issues with the bind mounts needed for DraStic Steward and PM.
# Alert users to this if they have selected Steward but can't run it.

display_bad_flip_firmware_message() {
	start_pyui_message_writer
	log_and_display_message "There appears to be an issue with your setup.\nPlease ensure you're on the latest Miyoo Flip firmware."
	sleep 5
	stop_pyui_message_writer
}


##### MIYOOMINI #####

# Only Steward version is available on MM family. Hardcode this "core" selection.

run_drastic_MiyooMini() {
	export CORE="DraStic-Steward"

	nds_emu_dir=/mnt/SDCARD/Emu/NDS
	export HOME=$nds_emu_dir
	export PATH=$nds_emu_dir:$PATH
	export LD_LIBRARY_PATH=$nds_emu_dir/libs_MiyooMini:$LD_LIBRARY_PATH
	export SDL_VIDEODRIVER=mmiyoo
	export SDL_AUDIODRIVER=mmiyoo
	export EGL_VIDEODRIVER=mmiyoo

	cp -f $nds_emu_dir/resources/overlay/grid-empty.png $nds_emu_dir/resources/overlay/grid.png

	killall audioserver

	sv=`cat /proc/sys/vm/swappiness`

	# 60 by default
	echo 10 > /proc/sys/vm/swappiness

	cd $nds_emu_dir

	set_performance
	log_message "Running DraStic-Steward on MiyooMini"
	ready_arch_32_states
	./drastic32 "$ROM_FILE"
	stash_arch_32_states
	sync
	echo $sv > /proc/sys/vm/swappiness
}

##### BRICK #####

run_drastic_Brick(){
	if [ "$CORE" = "DraStic-Steward" ]; then
		run_drastic_steward_Brick
	elif [ "$CORE" = "DraStic-original" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64 
		run_drastic64
	elif [ "$CORE" = "DraStic-trngaje" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
		run_drastic_trngaje_a133p
	else
		display_core_unrecognized_for_platform_message
	fi
}

run_drastic_steward_Brick() {
	#Drastic steward depends on something MainUI setups
    /usr/trimui/bin/MainUI &
    pid=$!
    sleep 2
    kill "$pid"

	kill_runner
	LD_LIBRARY_PATH=/usr/trimui/lib ./runner&
	sleep 1
	export SDL_VIDEODRIVER=NDS
	ready_arch_32_states
	./lib32_Brick/ld-linux-armhf.so.3 --library-path lib32_Brick ./drastic32 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	stash_arch_32_states
	sync
	kill_runner
}

kill_runner() {
    PID="$(pidof runner)"
    if [ "$PID" != "" ]; then
        kill -9 $PID
    fi
}

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

##### SMART PRO S #####

# Only original version is currently available on TSPS. Hardcode this "core" selection.

run_drastic_SmartProS() {
	export CORE="DraStic-original"
	run_drastic64
}

##### PIXEL 2 #####

run_drastic_Pixel2() {
	if [ "$CORE" = "DraStic-stock" ]; then
		run_drastic_stock_Pixel2
	elif [ "$CORE" = "DraStic-trngaje" ]; then
		run_drastic_trngaje_Pixel2
	else
		display_core_unrecognized_for_platform_message
	fi
}

run_drastic_stock_Pixel2() {
	ready_arch_64_states
	pin_to_dedicated_cores drastic64 2
	# Disable loging for now, it's writting a lot to it
	./drastic64 "$ROM_FILE" # > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	stash_arch_64_states
}

run_drastic_trngaje_Pixel2() {
	export LD_LIBRARY_PATH="$HOME/lib64_Pixel2_trngaje:$LD_LIBRARY_PATH"
	./drastic "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
}


##### CONFIG HANDLING #####

# Configs are set PER-DEVICE, but are currently shared by all variants of DraStic on that device.

load_drastic_configs() {
	CFG_DIR="/mnt/SDCARD/Emu/NDS/config"
	RES_DIR="/mnt/SDCARD/Emu/NDS/resources"
	cp -f "$CFG_DIR/drastic-$PLATFORM.cfg" "$CFG_DIR/drastic.cfg"
	[ -f "$RES_DIR/settings_${PLATFORM}.json" ] && cp "$RES_DIR/settings_${PLATFORM}.json" "$RES_DIR/settings.json"
}

save_drastic_configs() {
	CFG_DIR="/mnt/SDCARD/Emu/NDS/config"
	RES_DIR="/mnt/SDCARD/Emu/NDS/resources"
	cp -f "$CFG_DIR/drastic.cfg" "$CFG_DIR/drastic-$PLATFORM.cfg"
	[ -f "$RES_DIR/settings.json" ] && cp "$RES_DIR/settings.json" "$RES_DIR/settings_${PLATFORM}.json"
}


##### SAVE STATE HANDLING #####

# The 32-bit versions are used exclusively with Steward, REGARDLESS of host device's bitness.
# All original and trngaje versions should use the 64-bit states.

ready_arch_64_states() {
	[ -d "$EMU_DIR/backup-64" ] && mv "$EMU_DIR/backup-64" "$EMU_DIR/backup"
}

ready_arch_32_states() {
	[ -d "$EMU_DIR/backup-32" ] && mv "$EMU_DIR/backup-32" "$EMU_DIR/backup"
}

stash_arch_64_states() {
	[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-64"
}

stash_arch_32_states() {
	[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-32"
}
