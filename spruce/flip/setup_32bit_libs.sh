#!/bin/sh
set -e  # Exit immediately if a command exits with a non-zero status

# Where the ext4 magic sits in the image, and its bytes as od prints them.
EXT4_SUPERBLOCK_OFFSET=1024
EXT4_MAGIC_FIELD_OFFSET=56
EXT4_MAGIC_LE="53ef"

die() {
	echo "Error: $1"
	exit 1
}

# Checks whether the overlay image holds an ext4 superblock; returns 0 if it does.
image_is_ext4() {
	magic="$(od -A n -t x1 -j $((EXT4_SUPERBLOCK_OFFSET + EXT4_MAGIC_FIELD_OFFSET)) -N 2 "/mnt/SDCARD/Persistent/.32bit_merge/ext4.img" 2>/dev/null | tr -d ' ')"
	[ "$magic" = "$EXT4_MAGIC_LE" ]
}

mount_ext4() {
	mount -o loop "/mnt/SDCARD/Persistent/.32bit_merge/ext4.img" "/mnt/SDCARD/Persistent/.32bit_merge/ext4" || die "Failed to mount ext4.img"
}

bind_usr() {
	mount -t overlay overlay -o lowerdir=/usr,upperdir=/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/upper,workdir=/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/work /mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/merged_usr || die "Overlay mount failed"
	mount --bind "/mnt/SDCARD/Persistent/.32bit_merge/ext4/usr/merged_usr" /usr || die "Bind mount to /usr failed"
}

# An image made while mkfs.ext4 was missing is zero-filled.
if ! image_is_ext4; then
	command -v mkfs.ext4 >/dev/null || die "mkfs.ext4 not found"
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