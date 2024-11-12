#!/bin/sh

CONFIG="/mnt/SDCARD/Emu/FAKE08/config.json"
IMG_SHOWN="/mnt/SDCARD/Roms/FAKE08/Imgs"
IMG_HIDDEN="/mnt/SDCARD/Roms/FAKE08/.Imgs"
CACHE="/mnt/SDCARD/Roms/FAKE08/FAKE08_cache6.db"
MGL="/mnt/SDCARD/Roms/FAKE08/miyoogamelist.xml"

if [ "$1" = "on" ]; then
	# use carts as box art
	sed -i 's%\"imgpath\": \"../../Roms/FAKE08/Imgs\",%\"imgpath\": \"../../Roms/FAKE08\",%' "$CONFIG"

	# hide Imgs folder so it doesn't appear in games list
	mv "$IMG_SHOWN" "$IMG_HIDDEN"

	# enable PNG extension files to appear in MainUI
	sed -i 's%\"extlist\": \"p8\",%\"extlist\": \"p8|png\",%' "$CONFIG"

	# remove db and xml files to refresh game list
	rm "$CACHE"
	rm "$MGL"
else
	# use Imgs folder for box art
	sed -i 's%\"imgpath\": \"../../Roms/FAKE08\",%\"imgpath\": \"../../Roms/FAKE08/Imgs\",%' "$CONFIG"

	# return Imgs folder to its original location
	mv "$IMG_HIDDEN" "$IMG_SHOWN"

	# disallow PNG files from showing in Pico-8 game list in MainUI
	sed -i 's%\"extlist\": \"p8|png\",%\"extlist\": \"p8\",%' "$CONFIG"

	# remove db and xml files to refresh game list
	rm "$CACHE"
	rm "$MGL"
fi
