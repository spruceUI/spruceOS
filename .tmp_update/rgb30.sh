#!/bin/sh
#
# spruce entry point for the Powkiddy RGB30 (Rockchip RK3566).
#
# Reached from MossySpruce, which is our fork of Shaun Inman's Moss (itself a
# fork of JELOS) living on TF1:
#
#   spruce.service -> /usr/bin/start_spruce.sh -> /mnt/SDCARD/.tmp_update/rgb30.sh
#
# /mnt/SDCARD is a symlink to /storage/roms baked into the MossySpruce image.
# TF2 is mounted there by jelos-automount before the UI service starts.
#
# See github.com/Sundownersport/MossySpruce -- packages/ui/spruce.

/mnt/SDCARD/spruce/scripts/runtime.sh
