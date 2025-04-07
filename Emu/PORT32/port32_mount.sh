#!/bin/sh
mount -t squashfs miyoo355_rootfs_32.img mnt
mount --bind /sys mnt/sys
mount --bind /dev mnt/dev
mount --bind /proc mnt/proc
mount --bind /var/run mnt/var/run
mount --bind /mnt/sdcard mnt/sdcard
mkdir -p mnt/mnt
mkdir -p mnt/mnt/sdcard
mount --bind /mnt/sdcard mnt/mnt/sdcard
mount --bind /mnt/sdcard/Roms/PORTS64/ mnt/sdcard/Roms/PORTS/
mount --bind mnt/sdcard/Roms/PORTS64/ mnt/sdcard/MIYOO_EX/ports/
mount --bind mnt/sdcard/MIYOO_EX/PortMaster mnt/sdcard/MIYOO_EX/PortMaster/PortMaster  

