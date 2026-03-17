#!/bin/bash

. /mnt/SDCARD/spruce/scripts/platform/device_functions/AnbernicXXCommon.sh


# Will miyoo ones work?
setup_for_retroarch_and_get_bin_location(){
	#RA_DIR="/mnt/vendor/deep/retro"
    #export RA_BIN="retroarch"
    #export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"


    #/mnt/SDCARD/RetroArch/.config/retroarch/autoconfig/sdl2
	RA_DIR="/mnt/SDCARD/RetroArch"
	export RA_BIN="ra64.universal"
    export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores64"


	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi
    
    cp /mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRGCubeXX-universal.cfg /mnt/SDCARD/RetroArch/.config/retroarch/retroarch.cfg
    
    echo "$RA_BIN"
}