#!/bin/sh

# Requires globals:
#   PLATFORM
#   EMU_DIR
#   ROM_FILE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Requires functions:
#   log_message
#
# Provides:
#   run_xroar

run_xroar() {

XROAR_BIN="xroar"


LD_LIBRARY_PATH="$XROAR_DIR/libs:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH

HOME="$(GET_VAR "device" "board/home")"
export HOME

SETUP_SDL_ENVIRONMENT

SET_VAR "system" "foreground_process" "$XROAR_BIN"

case "$CORE" in
	xroar | ext-xroar) CORE="coco2bus" ;;
esac

XR_GPTK="$EMU_DIR/gptk"

GAME_BN=$(basename "${FILE%.*}")
GPTK_SP="${XR_GPTK}/${GAME_BN}.gptk"

[ ! -f "$GPTK_SP" ] && GPTK_SP="${XR_GPTK}/$XROAR_BIN.gptk"

/mnt/SDCARD/spruce/bin64/gptokeyb "$XROAR_BIN" -c "$GPTK_SP" &

"$EMU_DIR/$XROAR_BIN" -c "$EMU_DIR/$XROAR_BIN.conf" -default-machine coco2bus "$ROMFILE"

}
