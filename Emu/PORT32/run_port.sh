#!/bin/sh

export HOME="/mnt/sdcard/spruce/flip/home"
export LD_LIBRARY_PATH="/mnt/sdcard/spruce/flip/lib32/:/mnt/sdcard/spruce/flip/muOS/usr/lib32:$LD_LIBRARY_PATH"
export PATH="/mnt/sdcard/spruce/flip/muOS/usr/bin:$PATH"

rm /mnt/sdcard/spruce/logs/port32.log
/mnt/sdcard/Emu/PORT32/scan_for_segfault.sh &
scanner_pid=$!

"$1" &> /mnt/sdcard/spruce/logs/port32.log
kill "$scanner_pid"
