#!/bin/sh

cd "$(dirname "$0")"
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
"$(get_python_path)" ./updater.py
