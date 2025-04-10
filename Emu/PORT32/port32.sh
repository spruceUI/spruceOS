#!/bin/sh
echo pwd : $(pwd)

echo "Executing exec_chroot.sh $1"
./exec_chroot.sh "$1" &> /mnt/sdcard/spruce/logs/exec_chroot.log
