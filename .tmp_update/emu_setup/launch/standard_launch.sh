#!/bin/sh

export RA_DIR="/mnt/SDCARD/RetroArch"
export EMU_DIR="$(dirname "$0")"
export GAME="$(basename "$1")"
export OVR_DIR="$EMU_DIR/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"
export LAST_GAME="/mnt/SDCARD/.tmp_update/flags/.lastgame"
export GS_LOG="/mnt/SDCARD/.tmp_update/emu_setup/gs.log"

. /mnt/SDCARD/.tmp_update/scripts/keycodes.sh
. "$EMU_DIR/default.opt"
. "$EMU_DIR/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

call_gs() {
	killall -15 retroarch || killall -15 /mnt/SDCARD/RetroArch/retroarch || killall -15 ra32.miyoo || killall -15 /mnt/SDCARD/RetroArch/ra32.miyoo
	touch "/mnt/SDCARD/.tmp_update/flags/gs_activated"
	sleep 1
}

/mnt/SDCARD/App/utils/utils $GOV $CORES $CPU $GPU $DDR $SWAP

exec_on_hotkey "call_gs" "$B_B" "$B_DOWN" "$B_L2" "$B_R2" &
echo $0 $*

cd "$RA_DIR"
HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"
if [ -f "/mnt/SDCARD/.tmp_update/flags/gs_activated" ]; then
	"/mnt/SDCARD/.tmp_update/scripts/gs.sh"
fi

# save this if-then-fi block for SS mode
# if ! grep -q `cat $LAST_GAME` "$GS_LOG"; then
#	awk 1 "$LAST_GAME" >> "$GS_LOG"
# fi

#if log exceeds 5 entries, keep only the last 5.
if [ `wc -l "$GS_LOG"` -gt 5 ]; then
	GS_TEMP=`tail -n 5 "$GS_LOG"`
	echo "$GS_TEMP" > "$GS_LOG"
fi
