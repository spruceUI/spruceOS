#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BBS_PATH="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8/bbs"
ROM_PATH="/mnt/SDCARD/Roms/PICO8"
FAVE_PATH="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8/favourites.txt"

{
for cart in "$BBS_PATH"/*/*.p8.png ; do
	cartname="$(basename "$cart")"
	shortname="$(basename "$cart" .p8.png)"
	if [ -s "${cart}" ]; then
		cp -f "$cart" "$ROM_PATH/$cartname"
		log_message "$cartname imported to $ROM_PATH"
		
		if grep -q "$shortname" "$FAVE_PATH"; then
			newname="$(awk -F '|' -v term="$shortname" '$2 ~ term {print $7}' $FAVE_PATH)"
			if [ -n "$newname" ]; then 
				mv -f "$ROM_PATH/$cartname" "$ROM_PATH/$newname.p8.png"
				log_message "renamed $cartname to $newname.p8.png"
			else
				log_message "no new name found for $cartname"
			fi
		else
			log_message "$cartname is not in favorites - skipping renaming logic"
		fi
	fi
done
} &

display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png" -t "Importing carts from Splore" -d 2

rm -f "$ROM_PATH/PICO8_cache6.db"
log_message "Done importing. Pico-8 romlist refreshed."
