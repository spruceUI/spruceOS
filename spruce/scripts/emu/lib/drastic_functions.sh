#!/bin/sh

##### TODO: HOOK UP TRNGAJE's DRASTIC FOR BRICK
##### TODO: HOOK UP CORE SWITCH B/T TRNGAJE AND OG DRASTIC on SMART PRO; no Steward available

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
#   kill_runner
#   load_drastic_configs
#   save_drastic_configs

run_drastic() {
	load_drastic_configs
	#Why do we use grid on NDS but no other systems?
	cp -f $nds_emu_dir/resources/overlay/grid-enabled.png $nds_emu_dir/resources/overlay/grid.png

	export HOME=$EMU_DIR
	cd $EMU_DIR
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	[ -f "$EMU_DIR/resources/settings_${PLATFORM}.json" ] && cp "$EMU_DIR/resources/settings_${PLATFORM}.json" "$EMU_DIR/resources/settings.json"

	if [ "$PLATFORM" = "A30" ]; then # only Steward is available.
		run_drastic_steward_A30

	elif [ "$PLATFORM" = "MiyooMini" ]; then # only Steward is available.
		run_drastic_steward_MiyooMini

	else # 64-bit platform
		[ -d "$EMU_DIR/backup-64" ] && mv "$EMU_DIR/backup-64" "$EMU_DIR/backup"	# ready arch dependent states
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
		
		if [ "$PLATFORM" = "Brick" ]; then
			if [ "$CORE" = "DraStic-Steward" ]; then
				run_drastic_steward_Brick
			else 
				run_drastic64
			fi

		elif [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "SmartProS" ]; then
			export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64_a133p"
			export SDL_AUDIODRIVER=dsp
			run_drastic64

		elif [ "$PLATFORM" = "Flip" ]; then
			if [ -d /usr/l32 ] && [ "$CORE" = "DraStic-Steward" ]; then
				run_drastic_steward_Flip

			elif [ "$CORE" = "DraStic-trngaje" ]; then
				run_drastic_trngaje_Flip

			else
				run_drastic64 		# if overlay mount of /usr fails, fall back to original DraStic instead of Steward's
			fi

		elif [ "$PLATFORM" = "Pixel2" ]; then
			run_drastic_Pixel2
		fi

		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-64"	# stash arch dependent states
	fi

	[ -f "$EMU_DIR/resources/settings.json" ] && cp "$EMU_DIR/resources/settings.json" "$EMU_DIR/resources/settings_${PLATFORM}.json"
	sync
	save_drastic_configs
}

run_drastic64() {
	pin_to_dedicated_cores drastic64 2
	./drastic64 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
}

run_drastic_steward_A30() {
	[ -d "$EMU_DIR/backup-32" ] && mv "$EMU_DIR/backup-32" "$EMU_DIR/backup"	# ready arch dependent states
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
	[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-32"		# stash arch dependent states
}

run_drastic_steward_MiyooMini() {
	[ -d "$EMU_DIR/backup-32" ] && mv "$EMU_DIR/backup-32" "$EMU_DIR/backup"	# ready arch dependent states


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
	./drastic32 "$ROM_FILE"
	sync

	echo $sv > /proc/sys/vm/swappiness

}

run_drastic_steward_Brick() {
	#Drastic steward depends on something MainUI setups
    #/usr/trimui/bin/MainUI &
    #pid=$!
    #sleep 2
    #kill "$pid"

	kill_runner
	LD_LIBRARY_PATH=/usr/trimui/lib ./runner&
	sleep 1
	export SDL_VIDEODRIVER=NDS
	./lib32_Brick/ld-linux-armhf.so.3 --library-path lib32_Brick ./drastic32 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	sync
	kill_runner
}

run_drastic_steward_Flip() {
	export SDL_VIDEODRIVER=NDS
	export LD_LIBRARY_PATH="$HOME/lib32_Flip:/usr/lib32:$LD_LIBRARY_PATH"
	./drastic32 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
}

run_drastic_trngaje_Flip() {
	export LD_LIBRARY_PATH="$HOME/lib64_Flip:$LD_LIBRARY_PATH"
	mv ./drastic64 ./drastic
	./drastic "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	mv ./drastic ./drastic64
}

run_drastic_Pixel2() {
	pin_to_dedicated_cores drastic64 2
	# Disable loging for now, it's writting a lot to it
	./drastic64 "$ROM_FILE" # > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
}

kill_runner() {
    PID="$(pidof runner)"
    if [ "$PID" != "" ]; then
        kill -9 $PID
    fi
}

load_drastic_configs() {
	DS_DIR="/mnt/SDCARD/Emu/NDS/config"
	cp -f "$DS_DIR/drastic-$PLATFORM.cfg" "$DS_DIR/drastic.cfg"
}

save_drastic_configs() {
	DS_DIR="/mnt/SDCARD/Emu/NDS/config"
	cp -f "$DS_DIR/drastic.cfg" "$DS_DIR/drastic-$PLATFORM.cfg"
}
