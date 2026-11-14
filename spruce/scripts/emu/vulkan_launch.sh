#!/bin/sh
# For systems whose RetroArch core should draw through Vulkan. On a device with
# a Vulkan driver (device_vulkan_env) run_retroarch switches to it; everywhere
# else this is standard_launch.sh.
export RA_VULKAN=1
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh "$@"
