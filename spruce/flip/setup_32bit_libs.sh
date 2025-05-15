#!/bin/sh
set -e  # Exit immediately if a command exits with a non-zero status

die() {
	echo "Error: $1"
	exit 1
}

mount_ext4() {
	mount -o loop "/mnt/SDCARD/Persistent/.32bit_merge/ext4.img" "/mnt/SDCARD/Persistent/.32bit_merge/ext4" || die "Failed to mount ext4.img"
}

bind_usr() {
	mount -t overlay overlay -o lowerdir=/usr,upperdir=/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/upper,workdir=/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/work /mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/merged_usr || die "Overlay mount failed"
	mount --bind "/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/merged_usr" /usr || die "Bind mount to /usr failed"
}

if [ ! -f "/mnt/SDCARD/Persistent/.32bit_merge/ext4.img" ]; then
	mkdir -p "/mnt/SDCARD/Persistent/.32bit_merge/ext4"

	dd if=/dev/zero of="/mnt/SDCARD/Persistent/.32bit_merge/ext4.img" bs=1M count=10
	mkfs.ext4 "/mnt/SDCARD/Persistent/.32bit_merge/ext4.img"
	mount_ext4

	mkdir -p "/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr"
	mkdir -p "/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/work"
	mkdir -p "/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/merged_usr"
	mkdir -p "/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/upper"

	bind_usr

	ln -s /mnt/SDCARD/Persistent/.32bit_chroot/usr/lib32/ /usr/lib32
	ln -s /mnt/SDCARD/Persistent/.32bit_chroot/usr/lib32/ /usr/l32
	ln -s /mnt/SDCARD/Persistent/.32bit_chroot/usr/lib32/ /usr/arm-linux-gnueabihf

	cp /mnt/SDCARD/spruce/flip/ld-linux-armhf.so.3 /usr/lib/

else
	mount_ext4
	bind_usr
fi