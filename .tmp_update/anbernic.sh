#!/bin/sh

[ -e /mnt/SDCARD ] || ln -s /mnt/sdcard /mnt/SDCARD
/mnt/SDCARD/spruce/scripts/runtime.sh
