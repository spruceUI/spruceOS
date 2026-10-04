#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

df -h "$SD_DEV" | awk 'NR==2 {print $3 " used of " $2}'