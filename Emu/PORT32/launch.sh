#!/bin/sh
MAINSDROOT="$(dirname $0)/../.."
ROMNAME="$1"
BASEROMNAME=${ROMNAME##*/}
ROMNAMETMP=${BASEROMNAME%.*}
ROMPATH=${ROMNAME%.*}
    cd $(dirname $0)
    mount -t squashfs miyoo355_rootfs_32.img mnt
    mount --bind /sys mnt/sys
    mount --bind /dev mnt/dev
    mount --bind /proc mnt/proc
    mount --bind /var/run mnt/var/run
    mount --bind /mnt/sdcard mnt/sdcard
    mkdir -p mnt/mnt
    mkdir -p mnt/mnt/sdcard
    mount --bind /mnt/sdcard mnt/mnt/sdcard
    mount --bind mnt/sdcard/Roms/PORTS/ mnt/sdcard/MIYOO_EX/ports/
    mount --bind mnt/sdcard/MIYOO_EX/PortMaster mnt/sdcard/MIYOO_EX/PortMaster/PortMaster  
    echo chroot mnt /bin/sh -c "${ROMNAME}"
#    umount mnt/sdcard
#    umount mnt/media/sdcard1
#    umount mnt/var/run
#    umount mnt/proc
#    umount mnt/sys
#    umount mnt/dev
#    umount mnt
