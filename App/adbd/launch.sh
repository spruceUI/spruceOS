#!/bin/sh
DIR=$(dirname "$0")
cd $DIR

# bail if already running
if pidof adbd >/dev/null 2>&1; then
	exit 0
fi

# WiFi comes up as the saved setting says; adbd is network ADB, so it needs WiFi on
sh /mnt/SDCARD/spruce/scripts/wifi.sh apply --wait

# surgical strike to nop /etc/profile
# because it brings up the entire system again
mount -o bind $DIR/profile /etc/profile

# actually launch adbd
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:.
./adbd &

