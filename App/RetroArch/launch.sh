#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
cd /mnt/SDCARD/RetroArch/
HOME=/mnt/SDCARD/RetroArch/ $progdir/ra32.miyoo -v
