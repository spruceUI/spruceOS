#!/bin/sh

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh

BBS_PATH="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8/bbs/carts"
ROM_PATH="/mnt/SDCARD/Roms/PICO8"

{
for cart in "$BBS_PATH"/* ; do
	cartname="$(basename "$cart")"
	cp -f "$cart" "$ROM_PATH/$cartname"
	log_message "$cartname imported to $ROM_PATH"
done
} &

display_text -t "Importing carts from Splore :)" -d 2

rm -f "$ROM_PATH/PICO8_cache6.db"
log_message "Done importing. Pico-8 romlist refreshed."