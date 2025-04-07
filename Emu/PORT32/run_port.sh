#!/bin/sh

export HOME="/mnt/sdcard/spruce/flip/home"
export LD_LIBRARY_PATH="/mnt/sdcard/spruce/flip/lib32/:$LD_LIBRARY_PATH"
export PATH="/mnt/sdcard/spruce/flip/bin32/:$PATH"

echo executing $1
$1 &> /mnt/sdcard/spruce/logs/port32.log


