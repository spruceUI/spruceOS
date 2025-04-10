#!/bin/sh
echo pwd : $(pwd)

./port32_mount.sh &> /mnt/sdcard/spruce/logs/port32_mount.log
echo "Executing exec_chroot.sh $1"
./exec_chroot.sh "$1" &> /mnt/sdcard/spruce/logs/exec_chroot.log
./port32_umount.sh &> /mnt/sdcard/spruce/logs/port32_umount.log
