#!/bin/sh
# Vulkan only where the device defines device_vulkan_env; elsewhere standard_launch.sh
export RA_VULKAN=1
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh "$@"
