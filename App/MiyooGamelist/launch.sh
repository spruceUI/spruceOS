#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
start_pyui_message_writer
"$(get_python_path)" "$(dirname "$0")/generate.py"
auto_regen_tmp_update
