#!/bin/sh

if [ -f "/mnt/SDCARD/spruce/flip/miyoo355_rootfs_32.img_partaa" ]; then
    rm /mnt/SDCARD/spruce/flip/miyoo355_rootfs_32.img
    cat /mnt/SDCARD/spruce/flip/miyoo355_rootfs_32.img_part* > /mnt/SDCARD/spruce/flip/miyoo355_rootfs_32.img
    rm /mnt/SDCARD/spruce/flip/miyoo355_rootfs_32.img_part*
fi

if [ -f "/mnt/SDCARD/spruce/flip/muOS-pixie-reduced.sqsh-partaa" ]; then
    rm /mnt/SDCARD/spruce/flip/muOS-pixie-reduced.sqsh
    cat /mnt/SDCARD/spruce/flip/muOS-pixie-reduced.sqsh-part* > /mnt/SDCARD/spruce/flip/muOS-pixie-reduced.sqsh
    rm /mnt/SDCARD/spruce/flip/muOS-pixie-reduced.sqsh-part*
fi

