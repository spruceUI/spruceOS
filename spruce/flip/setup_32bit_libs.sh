#!/bin/sh

mount_ext4() {
	mount -o loop "/mnt/sdcard/Persistent/.32bit_merge/ext4.img" "/mnt/sdcard/Persistent/.32bit_merge/ext4"
}

bind_usr(){
	mount -t overlay overlay -o lowerdir=/usr,upperdir=/mnt/sdcard/Persistent/.32bit_merge/ext4/usr/upper,workdir=/mnt/sdcard/Persistent/.32bit_merge/ext4/usr/work /mnt/sdcard/Persistent/.32bit_merge/ext4/usr/merged_usr
	mount --bind "/mnt/sdcard/Persistent/.32bit_merge/ext4/usr/merged_usr" /usr
}

if [ ! -f "/mnt/sdcard/Persistent/.32bit_merge/ext4.img" ]; then
	mkdir -p "/mnt/sdcard/Persistent/.32bit_merge/ext4"

	dd if=/dev/zero of="/mnt/sdcard/Persistent/.32bit_merge/ext4.img" bs=1M count=10
	mkfs.ext4 "/mnt/sdcard/Persistent/.32bit_merge/ext4.img"
	mount_ext4

	mkdir -p "/mnt/sdcard/Persistent/.32bit_merge/ext4/usr"
	mkdir -p "/mnt/sdcard/Persistent/.32bit_merge/ext4/usr/work"
	mkdir -p "/mnt/sdcard/Persistent/.32bit_merge/ext4/usr/merged_usr"
	mkdir -p "/mnt/sdcard/Persistent/.32bit_merge/ext4/usr/upper"

	bind_usr

	ln -s /mnt/sdcard/Persistent/.32bit_chroot/usr/lib32/ /usr/lib32
	ln -s /mnt/sdcard/Persistent/.32bit_chroot/usr/lib32/ /usr/l32
	ln -s /mnt/sdcard/Persistent/.32bit_chroot/usr/lib32/ /usr/arm-linux-gnueabihf
	
	cp /mnt/sdcard/spruce/flip/ld-linux-armhf.so.3 /usr/lib/

else
	mount_ext4
	bind_usr
fi


