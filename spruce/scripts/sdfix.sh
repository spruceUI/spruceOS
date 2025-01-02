#!/bin/sh

SCRIPT_PATH="/mnt/SDCARD/spruce/scripts"

MOUNT_MODE=$(mount | grep SDCARD | cut -d'(' -f 2 | cut -d',' -f 1)

if [ "$MOUNT_MODE" = "ro" ]; then #set to rw for testing
	echo
	echo "SDCARD detected in read-only (RO) mode."
	echo
	echo "SDCARD in RO mode signifies data corruption. Remaining in RO mode will result in errors while using spruce."
 	echo
 	echo "Attempt repair? Press [B] No, [A] Yes"
 	BUTTON=$($SCRIPT_PATH/read_button.sh A B)
	if [ "$BUTTON" = "A" ]; then
    	echo 
    	echo "Attempting repair of SDCARD, be patient!"
		umount -l /dev/mmcblk0p1
		/tmp/fsck.fat -v -a /dev/mmcblk0p1
		echo "Attempting to mount in RW mode."
		mount /dev/mmcblk0p1 /mnt/SDCARD
		sleep 2
	elif [ "$BUTTON" = "B" ]; then
    	echo 
    	echo "Repair bypassed."
    	echo "Attempting to remount in RW mode anyway."
    	mount -o remount,rw /dev/mmcblk0p1 /mnt/SDCARD
    	sleep 2
    fi
	
    # recheck if in RO mode
    MOUNT_MODE=$(mount | grep SDCARD | cut -d'(' -f 2 | cut -d',' -f 1)
    if [ "$MOUNT_MODE" = "rw" ]; then 
    	echo "SUCCESS: Mounted in RW mode."
    	echo
    	echo "Resuming boot in 10s."
    	sleep 10
    	echo __EXIT__
	    return 0
    else
	    echo "FAIL: Mounted in RO mode."
    	echo "WARNING: Expect errors!"
    	echo
    	echo "Resuming boot in 30s."
    	sleep 30
    	echo __EXIT__
	    return 0
    fi
else
	return 0
fi
