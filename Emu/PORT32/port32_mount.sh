#!/bin/sh
mkdir -p /mnt/sdcard/Emu/PORT32/mnt
mkdir -p /mnt/sdcard/Emu/PORT32/mnt/mnt
mkdir -p /mnt/sdcard/Emu/PORT32/mnt/mnt/sdcard

mount -t squashfs /mnt/sdcard/Emu/PORT32/miyoo355_rootfs_32.img /mnt/sdcard/Emu/PORT32/mnt

mount --bind /sys /mnt/sdcard/Emu/PORT32/mnt/sys
mount --bind /dev /mnt/sdcard/Emu/PORT32/mnt/dev
mount --bind /proc /mnt/sdcard/Emu/PORT32/mnt/proc
mount --bind /var/run /mnt/sdcard/Emu/PORT32/mnt/var/run
mount --bind /mnt/sdcard /mnt/sdcard/Emu/PORT32/mnt/sdcard
mount --bind /mnt/sdcard /mnt/sdcard/Emu/PORT32/mnt/mnt/sdcard
mount --bind /mnt/sdcard/Roms/PORTS64/ /mnt/sdcard/Emu/PORT32/mnt/sdcard/Roms/PORTS/
mount --bind /mnt/sdcard/Emu/PORT32/mnt/sdcard/Roms/PORTS64/ /mnt/sdcard/Emu/PORT32/mnt/sdcard/MIYOO_EX/ports/
mount --bind /mnt/sdcard/Emu/PORT32/mnt/sdcard/MIYOO_EX/PortMaster /mnt/sdcard/Emu/PORT32/mnt/sdcard/MIYOO_EX/PortMaster/PortMaster  

chroot /mnt/sdcard/Emu/PORT32/mnt /bin/sh -c "/mnt/sdcard/spruce/flip/mount_muOS.sh"
