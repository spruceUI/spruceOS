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
#   kill_runner
#   load_drastic_configs
#   save_drastic_configs

run_drastic() {
	export HOME=$EMU_DIR
	cd $EMU_DIR

	if [ "$PLATFORM" = "A30" ]; then # only Steward is available.

		[ -d "$EMU_DIR/backup-32" ] && mv "$EMU_DIR/backup-32" "$EMU_DIR/backup"
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
		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-32"

	else # 64-bit platform

		[ -d "$EMU_DIR/backup-64" ] && mv "$EMU_DIR/backup-64" "$EMU_DIR/backup"
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
		
		if [ "$PLATFORM" = "Brick" ]; then
			if [ "$CORE" = "DraStic-Steward" ]; then
				kill_runner
				LD_LIBRARY_PATH=/usr/trimui/lib ./runner&
				sleep 1
				export SDL_VIDEODRIVER=NDS
				./lib32_Brick/ld-linux-armhf.so.3 --library-path lib32_Brick ./drastic32 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
				sync
				kill_runner
			else 

				##### TODO: HOOK UP TRNGAJE's DRASTIC FOR BRICK

				./drastic64 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
			fi

		elif [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "SmartProS" ]; then

			##### TODO: HOOK UP CORE SWITCH B/T TRNGAJE AND OG DRASTIC on SMART PRO; no Steward available

			pin_to_dedicated_cores drastic64 2
			export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64_a133p"
			export SDL_AUDIODRIVER=dsp
			./drastic64 "$ROM_FILE" > $LOG_DIR/drastic-og-smartpro.log 2>&1

		elif [ "$PLATFORM" = "Flip" ]; then

			if [ -d /usr/l32 ] && [ "$CORE" = "DraStic-Steward" ]; then
				export SDL_VIDEODRIVER=NDS
				export LD_LIBRARY_PATH="$HOME/lib32_Flip:/usr/lib32:$LD_LIBRARY_PATH"
				./drastic32 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

			elif [ "$CORE" = "DraStic-trngaje" ]; then
				export LD_LIBRARY_PATH="$HOME/lib64_Flip:$LD_LIBRARY_PATH"
				mv ./drastic64 ./drastic
				./drastic "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
				mv ./drastic ./drastic64
			else
				# if overlay mount of /usr fails, fall back to original DraStic instead of Steward's
				./drastic64 "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
			fi
		fi
		
		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-64"
	fi
	sync
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