#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export EMU_DIR="/mnt/SDCARD/Emu/SCUMMVM"

case "$PLATFORM" in
    "A30")
        SCUMMVM_BIN="$EMU_DIR/scummvm.a30"
        export LD_LIBRARY_PATH="$EMU_DIR/liba30:$LD_LIBRARY_PATH"
        ;;
    "MiyooMini")
        SCUMMVM_BIN="$EMU_DIR/scummvm.mini"
        export LD_LIBRARY_PATH="$EMU_DIR/libmini:$LD_LIBRARY_PATH"
        ;;
    *)
        SCUMMVM_BIN="$EMU_DIR/scummvm.64"
        export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
        ;;
esac

start_pyui_message_writer

"$SCUMMVM_BIN" --config=/dev/null --list-games > /tmp/scvm_gameid.txt

"$(get_python_path)" "$(dirname "$0")/gamelist.py"
auto_regen_tmp_update

rm -f /tmp/scvm_gameid.txt

stop_pyui_message_writer