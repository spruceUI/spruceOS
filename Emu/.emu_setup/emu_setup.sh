#!/bin/sh

EMU_DIR="/mnt/SDCARD/Emu"
SETUP_DIR="$EMU_DIR/.emu_setup"
OPT_DIR="$SETUP_DIR/options"
DEF_DIR="$SETUP_DIR/defaults"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# copy defaults folder into options folder if needed
if [ ! -d "$OPT_DIR" ]; then
	cp -rf "$DEF_DIR" "$OPT_DIR" && log_message "emu_setup.sh: copied $DEF_DIR into $OPT_DIR"
else
	log_message "emu_setup.sh: $OPT_DIR already exists"
fi

# copy standard RA launch scripts to all Emu subfolders
for dir in $EMU_DIR/* ; do
	if [ -d $dir ] && [ ! -f $dir/launch.sh ]; then
		cp -f "$SETUP_DIR/redirect_launch.sh" "$dir/launch.sh" && log_message "emu_setup.sh: copied launch.sh to $dir"
	fi
done

# move .config folder into place at SD root
if [ ! -d "/mnt/SDCARD/.config" ]; then
	if [ -d "$SETUP_DIR/.config" ]; then
		cp -rf "$SETUP_DIR/.config" "/mnt/SDCARD/.config" && log_message "emu_setup.sh: copied .config folder to root of SD card."
	else
		log_message "emu_setup.sh: WARNING!!! No .config folder found!"
	fi
else
	log_message "emu_setup.sh: .config folder already in place at SD card root."
fi

# create splore launcher if it doesn't already exist
if [ ! -f "$SPLORE_CART" ]; then
	touch "$SPLORE_CART" && log_message "emu_setup.sh: created $SPLORE_CART"
else
	log_message "emu_setup.sh: $SPLORE_CART already found."
fi
