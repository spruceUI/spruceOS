#!/bin/sh
# will be copied to /miyoo355/app/355/ during build

set -x

# get path of script
DIR="$(cd "$(dirname "$0")" && pwd)"

# File locations
# New payload 				$DIR/payload/runmiyoo.sh
# Old payload or original	/usr/miyoo/bin/runmiyoo.sh
# Original after install	/usr/miyoo/bin/runmiyoo-original.sh

# Sample version string for payload... ToDo: Remember to add to payload
# PAYLOAD_VERSION 20250518

# Get new payload version
NEW_PAYLOAD_VERSION=$(cat $DIR/payload/runmiyoo.sh | grep PAYLOAD_VERSION | awk '{print $3}')
echo "New payload version $NEW_PAYLOAD_VERSION"

# delete FW image from SD card if we make it to this script, which would imply we are already
# on a fresh FW flash and want to install our .tmp_update hook and not immediately reflash the FW.
[ -f "/mnt/SDCARD/miyoo355_fw.img" ] && rm "/mnt/SDCARD/miyoo355_fw.img"

# Check for existing install
if [ ! -f /usr/miyoo/bin/runmiyoo-original.sh ]; then
	# Payload not installed
	INSTALLED_PAYLOAD_VERSION=0
else
	# Check if payload has version string. Returns number of lines with PAYLOAD_VERSION in it
	PAYLOAD_HAS_VERSION=$(cat /usr/miyoo/bin/runmiyoo.sh | grep -c PAYLOAD_VERSION)

	if [[ PAYLOAD_HAS_VERSION -eq 0 ]]; then
		# Payload installed but has no version.
		INSTALLED_PAYLOAD_VERSION=1
		echo "Old payload has no version"
	else
		# Get old payload version
		OLD_PAYLOAD_VERSION=$(cat /usr/miyoo/bin/runmiyoo.sh | grep PAYLOAD_VERSION | awk '{print $3}')
		echo "Old payload $OLD_PAYLOAD_VERSION"

		# Compare payload versions
		if [[ $NEW_PAYLOAD_VERSION -le $OLD_PAYLOAD_VERSION ]]; then
			echo "Payload is up to date"
			exit 0	
		fi
	fi
fi

#debug delay
sleep 5s

export PATH=/tmp/bin:$DIR/payload/bin:$PATH
export LD_LIBRARY_PATH=/tmp/lib:$DIR/payload/lib:$LD_LIBRARY_PATH

LAST_CALL_TIME=0
hide() {
	# killall show.elf || true
	touch /tmp/fbdisplay_exit
}
show() {
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - LAST_CALL_TIME)) -lt 2 ]; then
		DELAY=$((2 - (CURRENT_TIME - LAST_CALL_TIME)))
		echo "delay for $DELAY seconds"
        sleep $DELAY
    fi
    
    hide
    # show.elf $DIR/res/$1 300 &
    /usr/bin/fbdisplay $DIR/res/$1 &
    LAST_CALL_TIME=$(date +%s)
}

show "prep-env.png"
echo "preparing environment"
cd "$DIR"
cp -r payload/* /tmp
cd /tmp

show "extract-root.png"
echo "extracting rootfs"
dd if=/dev/mtd3ro of=old_rootfs.squashfs bs=131072

show "unpack-root.png"
echo "unpacking rootfs"
unsquashfs old_rootfs.squashfs

show "inject-hook.png"
if [[ PAYLOAD_HAS_VERSION -eq 0 ]]; then
	echo "swapping runmiyoo.sh"
	mv squashfs-root/usr/miyoo/bin/runmiyoo.sh squashfs-root/usr/miyoo/bin/runmiyoo-original.sh
	mv runmiyoo.sh squashfs-root/usr/miyoo/bin/
else
	echo "updating runmiyoo.sh"
	mv -f runmiyoo.sh squashfs-root/usr/miyoo/bin/
fi

show "pack-root.png"
echo "packing updated rootfs"
mksquashfs squashfs-root new_rootfs.squashfs -comp gzip -b 131072 -noappend -exports -all-root -force-uid 0 -force-gid 0

# mount so reboot remains available
mkdir -p /tmp/rootfs
mount /tmp/new_rootfs.squashfs /tmp/rootfs
export PATH=/tmp/rootfs/bin:/tmp/rootfs/usr/bin:/tmp/rootfs/sbin:$PATH
export LD_LIBRARY_PATH=/tmp/rootfs/lib:/tmp/rootfs/usr/lib:$LD_LIBRARY_PATH

show "flash-root.png"
echo "flashing updated rootfs"
flashcp new_rootfs.squashfs /dev/mtd3 && sync

show "reboot.png"
echo "done, rebooting"
sleep 2
reboot
while :; do
	sleep 1
done
exit