#!/bin/sh

# Bind over the system's copy, but only where the system has one: a bind needs an
# existing target, and BaseOS-my355 lacks some of these names (libanl.so.1, for one).
SKIPPED=""
bind_lib() {
	if [ -e "$2" ]; then
		mount --bind "$1" "$2"
	else
		SKIPPED="$SKIPPED ${2##*/}"
	fi
}

bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libc.so.6 /usr/lib/libc.so.6
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/ld-linux-aarch64.so.1 /usr/lib/ld-linux-aarch64.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/ld-linux-armhf.so.3 /usr/lib/ld-linux-armhf.so.3
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libanl.so.1 /usr/lib/libanl.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libatomic.so /usr/lib/libatomic.so
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libatomic.so.1 /usr/lib/libatomic.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libatomic.so.1.2.0 /usr/lib/libatomic.so.1.2.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libblkid.so.1 /usr/lib/libblkid.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libblkid.so.1.1.0 /usr/lib/libblkid.so.1.1.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libcrypt.so.1 /usr/lib/libcrypt.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libdl.so.2 /usr/lib/libdl.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libfdisk.so.1 /usr/lib/libfdisk.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libfdisk.so.1.1.0 /usr/lib/libfdisk.so.1.1.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libgcc_s.so /usr/lib/libgcc_s.so
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libiw.so /usr/lib/libiw.so
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libiw.so.30 /usr/lib/libiw.so.30
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libm.so.6 /usr/lib/libm.so.6
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libmount.so.1 /usr/lib/libmount.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libmount.so.1.1.0 /usr/lib/libmount.so.1.1.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libnss_dns.so.2 /usr/lib/libnss_dns.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libnss_files.so.2 /usr/lib/libnss_files.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libpthread.so.0 /usr/lib/libpthread.so.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libresolv.so.2 /usr/lib/libresolv.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/librt.so.1 /usr/lib/librt.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libsmartcols.so.1 /usr/lib/libsmartcols.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libsmartcols.so.1.1.0 /usr/lib/libsmartcols.so.1.1.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libudev.so.1 /usr/lib/libudev.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libudev.so.1.6.3 /usr/lib/libudev.so.1.6.3
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libutil.so.1 /usr/lib/libutil.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libuuid.so.1 /usr/lib/libuuid.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib/libuuid.so.1.3.0 /usr/lib/libuuid.so.1.3.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/usr/lib/libstdc++.so /usr/lib/libstdc++.so
bind_lib /mnt/SDCARD/spruce/flip/muOS/usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6
bind_lib /mnt/SDCARD/spruce/flip/muOS/usr/lib/libstdc++.so.6.0.32 /usr/lib/libstdc++.so.6.0.29
bind_lib /mnt/SDCARD/spruce/flip/muOS/usr/lib/libstdc++.so.6.0.32-gdb.py /usr/lib/libstdc++.so.6.0.29-gdb.py
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/ld-linux-armhf.so.3 /usr/lib32/ld-linux-armhf.so.3
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libanl.so.1 /usr/lib32/libanl.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libatomic.so /usr/lib32/libatomic.so
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libatomic.so.1 /usr/lib32/libatomic.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libatomic.so.1.2.0 /usr/lib32/libatomic.so.1.2.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libblkid.so.1 /usr/lib32/libblkid.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libblkid.so.1.1.0 /usr/lib32/libblkid.so.1.1.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libc.so.6 /usr/lib32/libc.so.6
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libcrypt.so.1 /usr/lib32/libcrypt.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libdl.so.2 /usr/lib32/libdl.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libgcc_s.so /usr/lib32/libgcc_s.so
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libgcc_s.so.1 /usr/lib32/libgcc_s.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libm.so.6 /usr/lib32/libm.so.6
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libmount.so.1 /usr/lib32/libmount.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libmount.so.1.1.0 /usr/lib32/libmount.so.1.1.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libnss_dns.so.2 /usr/lib32/libnss_dns.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libnss_files.so.2 /usr/lib32/libnss_files.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libpthread.so.0 /usr/lib32/libpthread.so.0
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libresolv.so.2 /usr/lib32/libresolv.so.2
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/librt.so.1 /usr/lib32/librt.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libudev.so.1 /usr/lib32/libudev.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libudev.so.1.6.3 /usr/lib32/libudev.so.1.6.3
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libutil.so.1 /usr/lib32/libutil.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libuuid.so.1 /usr/lib32/libuuid.so.1
bind_lib /mnt/SDCARD/spruce/flip/muOS/lib32/libuuid.so.1.3.0 /usr/lib32/libuuid.so.1.3.0

if [ -n "$SKIPPED" ]; then
	echo "bind_glibc: not on this system, skipped:$SKIPPED"
fi
