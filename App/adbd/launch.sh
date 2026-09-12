#!/bin/sh
DIR=$(dirname "$0")
cd $DIR

# bail if already running
if pidof adbd >/dev/null 2>&1; then
	exit 0
fi

# load the wifi driver...from the SD card :lolsob:
insmod ./8188fu.ko

# superstitious ritual? nope!
/customer/app/axp_test wifion
sleep 2

# bring up wifi. Saved networks live on the card - see WPA_SUPPLICANT_FILE in
# helperFunctions.sh and the same call in platform/miyoo_mini_startup.sh. This
# used to point at /appconfigs, which PyUI no longer writes, so a network added
# in the UI would never reach adbd. Fall back to it for a card that predates
# the move.
WPA_CONF=/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf
[ -f "$WPA_CONF" ] || WPA_CONF=/appconfigs/wpa_supplicant.conf
ifconfig wlan0 up
wpa_supplicant -B -D nl80211 -iwlan0 -c "$WPA_CONF"
udhcpc -i wlan0 -s /etc/init.d/udhcpc.script &

# surgical strike to nop /etc/profile
# because it brings up the entire system again
mount -o bind $DIR/profile /etc/profile

# actually launch adbd
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:.
./adbd &

