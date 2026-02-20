#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/emu/lib/ppsspp_functions.sh

export HOME=/mnt/SDCARD/Saves
export EMU_DIR=/mnt/SDCARD/Emu/PSP/
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"

cd $EMU_DIR

move_dotconfig_into_place
load_ppsspp_configs
case "$PLATFORM" in
    "Brick"|"SmartPro") PPSSPPSDL="./PPSSPPSDL_TrimUI" ;;
    *) 					PPSSPPSDL="./PPSSPPSDL_${PLATFORM}" ;;
esac
/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
"$PPSSPPSDL" --fullscreen

save_ppsspp_configs
auto_regen_tmp_update
