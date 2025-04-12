#!/bin/sh
mkdir -p /mnt/sdcard/Roms/.32bit_chroot
mkdir -p /mnt/sdcard/Roms/.32bit_chroot/mnt
mkdir -p /mnt/sdcard/Roms/.32bit_chroot/mnt/sdcard

mount -t squashfs /mnt/sdcard/spruce/flip/miyoo355_rootfs_32.img /mnt/sdcard/Roms/.32bit_chroot

mount --bind /sys /mnt/sdcard/Roms/.32bit_chroot/sys
mount --bind /dev /mnt/sdcard/Roms/.32bit_chroot/dev
mount --bind /proc /mnt/sdcard/Roms/.32bit_chroot/proc
mount --bind /var/run /mnt/sdcard/Roms/.32bit_chroot/var/run
mount --bind /mnt/sdcard /mnt/sdcard/Roms/.32bit_chroot/sdcard
mount --bind /mnt/sdcard /mnt/sdcard/Roms/.32bit_chroot/mnt/sdcard
mount --bind /mnt/sdcard/Roms/PORTS64/ /mnt/sdcard/Roms/.32bit_chroot/sdcard/Roms/PORTS/
mount --bind /mnt/sdcard/Roms/.32bit_chroot/sdcard/Roms/PORTS64/ /mnt/sdcard/Roms/.32bit_chroot/mnt/sdcard/Roms/PORTS64/ports/

chroot /mnt/sdcard/Roms/.32bit_chroot /bin/sh -c "/mnt/sdcard/spruce/flip/mount_muOS.sh"
