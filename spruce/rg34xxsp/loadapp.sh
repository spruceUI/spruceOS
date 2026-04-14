#!/bin/bash

#
# add new bin,need test reboot or poweroff 
# see /etc/init.d/launcher.sh
#

export LD_LIBRARY_PATH=/usr/lib32:/usr/lib:/mnt/vendor/lib
#export LC_ALL=zh_CN.utf8
#export LANG=zh_CN.UTF-8
#export LANGUAGE="zh_CN:zh:en_US:en"

DEBUG="/mnt/data/xudebug.ini"
CHRGBIN="/mnt/vendor/bin/charg.dge"
StopBin="/tmp/stopAPP.ini"

check_swap_device()
{
# /etc/fstab add auto enable swap
SWAP_ST=`cat /proc/swaps | grep -e "mmcblk0p"`
VALUE=$?
if [ $VALUE -ne 0 ]; then
SWAP_DEVICE="/dev/mmcblk0p7"
	echo "-- need remount swapfs ---"
	
	mkswap  $SWAP_DEVICE
	swapon  $SWAP_DEVICE
fi
}

check_retroarch_cfg()
{
#HOME is different:~ -> /root or /
#RA_HEAD_DIR=~/.config/retroarch
RA_HEAD_DIR=/.config/retroarch
RA_ORI_CFG=/mnt/vendor/deep/retro/retroarch.cfg
	
	if [ ! -d $RA_HEAD_DIR ];then
		mkdir -p $RA_HEAD_DIR
	fi
	if [ ! -e "$RA_HEAD_DIR/retroarch.cfg" ];then
		cp $RA_ORI_CFG  $RA_HEAD_DIR/retroarch.cfg
	fi
}

RESIZE_ROOT_CMD()
{
# resize2fs 针对文件系统ext2 ext3 ext4
#
ROOT_DEVICE="/dev/mmcblk0p5"
RESIZE_FLG_FILE="/etc/allen_resize.cfg"

	if [ ! -f "$RESIZE_FLG_FILE" ]
	then
		echo "need resize $ROOT_DEVICE"
		touch $RESIZE_FLG_FILE
		
		resize2fs $ROOT_DEVICE
	fi
}

FORMAT_DATA_CMD()
{
DATA_DEVICE="/dev/mmcblk0p7"
DATA_DIR="/mnt/data"

	if [ -e "$DATA_DEVICE" ]
	then
		if [ ! -d "$DATA_DIR" ]; then
			echo "create $DATA_DIR"
			/bin/mkdir "$DATA_DIR"
		fi
		
		FORMAT=`/sbin/blkid $DATA_DEVICE | grep -e  "TYPE"`
		VALUE=$?
		if [ $VALUE -ne 0 ]; then
			echo "Start format $DATA_DEVICE ...."
			mkfs.ext4 $DATA_DEVICE
			sleep 0.5
			mount -t ext4 -o rw,noatime,nodiratime $DATA_DEVICE $DATA_DIR
		else
			
			mount -t ext4 -o rw,noatime,nodiratime $DATA_DEVICE $DATA_DIR
			
			INFO=`cat /proc/mounts | grep -e  "$DATA_DEVICE"`  
			VALUE=$?
			if [ $VALUE -ne 0 ]; then
				echo "$DATA_DEVICE don't mount!!,need format"
				mkfs.ext4 $DATA_DEVICE
				sleep 0.5
				mount -t ext4 -o rw,noatime,nodiratime $DATA_DEVICE $DATA_DIR
			fi
		fi
	fi
}

FORMAT_ROMS_CMD()
{
#
# os + game in one TF
#
#mount_options_vfat="rw,utf8,uid=1000,gid=1000,dmask=000,fmask=000,noatime,nodiratime"
mount_options_vfat="rw,utf8,dmask=000,fmask=000,noatime,nodiratime"
ROMS_DEVICE="/dev/mmcblk0p1"
if [ -e "/dev/mmcblk0p8" ]; then
	ROMS_DEVICE="/dev/mmcblk0p8"
fi
ROMS_DIR="/mnt/mmc"

	if [ -e "$ROMS_DEVICE" ]
	then
		if [ ! -d "$ROMS_DIR" ]; then
			echo "create $ROMS_DIR"
			/bin/mkdir "$ROMS_DIR"
		fi
		
		FORMAT=`/sbin/blkid $ROMS_DEVICE | grep -e  "TYPE"`
		VALUE=$?
		
		if [ $VALUE -ne 0 ]; then
			echo "Start format $ROMS_DEVICE ...."
			#mkfs.vfat $ROMS_DEVICE
			sleep 0.5
			#/sbin/parted /dev/mmcblk0 set 7 hidden off
			
			#mount -t vfat -o rw,utf8,noatime,nodiratime $ROMS_DEVICE $ROMS_DIR
			mount -t vfat -o $mount_options_vfat $ROMS_DEVICE $ROMS_DIR
		else
			
			#mount -t vfat -o rw,utf8,noatime,nodiratime $ROMS_DEVICE $ROMS_DIR
			mount -t vfat -o $mount_options_vfat $ROMS_DEVICE $ROMS_DIR
			
			INFO=`cat /proc/mounts | grep -e  "$ROMS_DEVICE"`  
			VALUE=$?
			if [ $VALUE -ne 0 ]; then
				echo "$ROMS_DEVICE don't mount!!,need format"
				#mkfs.vfat $ROMS_DEVICE
				sleep 0.5
				#mount -t vfat -o rw,utf8,noatime,nodiratime $ROMS_DEVICE $ROMS_DIR
				mount -t vfat -o $mount_options_vfat $ROMS_DEVICE $ROMS_DIR
			fi
		fi
	fi
}

export LD_LIBRARY_PATH=/mnt/vendor/lib:$LD_LIBRARY_PATH

RESIZE_ROOT_CMD
FORMAT_DATA_CMD
FORMAT_ROMS_CMD

if [ -f /mnt/mmc/appfs.img ]; then
#	umount /mnt/vendor
	mount /mnt/mmc/appfs.img /mnt/vendor
fi

check_retroarch_cfg

#check_swap_device

BOOT_MODE=`cat /sys/class/power_supply/axp2202-battery/boot_mode`
if [ $BOOT_MODE == 1 ];then
	rfkill block bluetooth
	systemctl stop bluetooth.service
	systemctl mask bluetooth.service
	
	rfkill block wifi
	systemctl stop NetworkManager.service
	systemctl mask NetworkManager.service
	
	if [ -f $CHRGBIN ]; then
		$CHRGBIN
		
	#run as follow cmd, if charg.dge run err
		sleep 5
		poweroff
	fi
else

# stop bt
#systemctl stop bluetooth
#rm -r /var/lib/bluetooth/*

	systemctl unmask NetworkManager.service
	systemctl restart NetworkManager.service
	rfkill unblock wifi
	
	systemctl unmask bluetooth.service
	systemctl restart bluetooth.service
	rfkill unblock bluetooth
fi

#----- sync local wall time to rtc time ------
#new rtc device need set once
RTC_DATE=`cat /sys/class/rtc/rtc0/date`
if [ x"$RTC_DATE" == x ]; then
SYS_DATE=`date "+%Y-%m-%d"`
	
	echo "must set rtc-device once"
	date -s  $SYS_DATE
	hwclock -w
fi

if [ -f /mnt/mmc/gpio_keys_polled.ko ]; then
	insmod /mnt/mmc/gpio_keys_gpadc.ko
	insmod /mnt/mmc/gpio_keys_polled.ko
fi

#---- third mod need this to mount sdcard ---
/mnt/vendor/ctrl/mmc_new.sh add

if [ -f "/mnt/mod/ctrl/autostart" ]; then
	/mnt/mod/ctrl/autostart
fi

while [ -f $DEBUG ]
do
	sleep 30
done


# Create symlink if it doesn't exist
if [ ! -e "/mnt/SDCARD" ]; then
    ln -s /mnt/sdcard /mnt/SDCARD
fi

# Default value
RunBin="/mnt/vendor/ctrl/dmenu_ln"

# Override if updater exists
if [ -f "/mnt/sdcard/.tmp_update/anbernic.sh" ]; then
    RunBin="/mnt/sdcard/.tmp_update/anbernic.sh"
fi

while [ -f $RunBin ]
do
	if [ -f $StopBin ];then
		echo "stop app run ..."
		#systemctl stop NetworkManager.service
		break
	fi
	
	$RunBin
done

