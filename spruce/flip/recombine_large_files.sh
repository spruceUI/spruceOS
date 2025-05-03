#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ -f "/mnt/sdcard/spruce/flip/miyoo355_rootfs_32.img_partaa" ]; then
    display -t "Setting up Miyoo355 32-bit rootfs"
    rm /mnt/sdcard/spruce/flip/miyoo355_rootfs_32.img
    cat /mnt/sdcard/spruce/flip/miyoo355_rootfs_32.img_part* > /mnt/sdcard/spruce/flip/miyoo355_rootfs_32.img
    rm /mnt/sdcard/spruce/flip/miyoo355_rootfs_32.img_part*
fi

if [ -f "/mnt/sdcard/spruce/flip/muOS-pixie-reduced.sqsh-partaa" ]; then
    display -t "Setting up libs for PortMaster (thanks muOS team!)"
    rm /mnt/sdcard/spruce/flip/muOS-pixie-reduced.sqsh
    cat /mnt/sdcard/spruce/flip/muOS-pixie-reduced.sqsh-part* > /mnt/sdcard/spruce/flip/muOS-pixie-reduced.sqsh
    rm /mnt/sdcard/spruce/flip/muOS-pixie-reduced.sqsh-part*
fi

