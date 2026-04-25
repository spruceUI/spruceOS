#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

df -h "$SD_DEV" | awk 'NR==2 {print $4 " / " $3}'