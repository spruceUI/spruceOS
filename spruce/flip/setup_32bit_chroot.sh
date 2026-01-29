#!/bin/sh
mkdir -p /mnt/SDCARD/Persistent/.32bit_chroot
mkdir -p /mnt/SDCARD/Persistent/.32bit_chroot/mnt
mkdir -p /mnt/SDCARD/Persistent/.32bit_chroot/mnt/sdcard

mount -t squashfs /mnt/SDCARD/spruce/flip/miyoo355_rootfs_32.img /mnt/SDCARD/Persistent/.32bit_chroot

mount --bind /sys /mnt/SDCARD/Persistent/.32bit_chroot/sys
mount --bind /dev /mnt/SDCARD/Persistent/.32bit_chroot/dev
mount --bind /proc /mnt/SDCARD/Persistent/.32bit_chroot/proc
mount --bind /var/run /mnt/SDCARD/Persistent/.32bit_chroot/var/run
mount --bind /mnt/sdcard /mnt/SDCARD/Persistent/.32bit_chroot/sdcard
mount --bind /mnt/sdcard /mnt/SDCARD/Persistent/.32bit_chroot/mnt/sdcard
mount --bind /mnt/SDCARD/Roms/PORTS/ /mnt/SDCARD/Persistent/.32bit_chroot/SDCARD/Roms/PORTS/
mount --bind /mnt/SDCARD/Persistent/.32bit_chroot/SDCARD/Roms/PORTS/ /mnt/SDCARD/Persistent/.32bit_chroot/mnt/SDCARD/Roms/PORTS/ports/

chroot /mnt/SDCARD/Persistent/.32bit_chroot /bin/sh -c "/mnt/SDCARD/spruce/flip/mount_muOS.sh"
