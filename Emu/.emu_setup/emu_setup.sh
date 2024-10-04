#!/bin/sh

EMU_DIR="/mnt/SDCARD/Emu"
SETUP_DIR="$EMU_DIR/.emu_setup"
OVR_DIR="$SETUP_DIR/overrides"
OPT_DIR="$SETUP_DIR/options"
CORE_DIR="$SETUP_DIR/core"
DEF_DIR="$SETUP_DIR/defaults"

{
# copy defaults folder into options folder if needed

if [ ! -d "$OPT_DIR" ]; then
	cp -rf "$DEF_DIR" "$OPT_DIR"
fi

for dir in $EMU_DIR/* ; do
	if [ -d $dir ]; then
		echo "dir is $dir";
		system="${dir##*/}" ;
		echo "system is $system";
# copy standard RA launch scripts to all Emu subfolders.
		cp -f "$SETUP_DIR/redirect_launch.sh" "$dir/launch.sh" && echo "copied launch.sh to $dir";
# delete config_hidden.json if a config.json already exists
		if [ -f "$dir/config.json" ] && [ -f "$dir/config_hidden.json" ]; then
			rm -f "$dir/config_hidden.json" && echo "removed duplicate config_hidden.json from $dir"
		fi
	fi
done

} &> "$SETUP_DIR/log.txt"
