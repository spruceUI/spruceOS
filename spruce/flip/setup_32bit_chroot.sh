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
# The rootfs image carries a /SDCARD/Roms/PORTS mount point; the card's
# folder is Roms/ports now. Inside the chroot /mnt/SDCARD is the card itself,
# so Roms/ports/<game> resolves there directly and needs no second bind.
mount --bind /mnt/SDCARD/Roms/ports/ /mnt/SDCARD/Persistent/.32bit_chroot/SDCARD/Roms/PORTS/

chroot /mnt/SDCARD/Persistent/.32bit_chroot /bin/sh -c "/mnt/SDCARD/spruce/flip/mount_muOS.sh"
