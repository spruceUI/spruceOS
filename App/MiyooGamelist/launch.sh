#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Disable idle/shutdown timer during gamelist generation
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

start_pyui_message_writer
"$(get_python_path)" "$(dirname "$0")/generate.py"
auto_regen_tmp_update
