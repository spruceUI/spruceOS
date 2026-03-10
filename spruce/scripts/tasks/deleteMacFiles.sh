#!/bin/sh

log_message "Cleaning up macOS junk files..."
result="$(python3 /mnt/SDCARD/spruce/scripts/tasks/deleteMacFiles.py)"
log_message "$result"
