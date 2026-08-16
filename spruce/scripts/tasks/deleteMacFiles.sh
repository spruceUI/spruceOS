#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "Cleaning up macOS junk files..."
result="$("$(get_python_path)" /mnt/SDCARD/spruce/scripts/tasks/deleteMacFiles.py)"
log_message "$result"
