#!/bin/sh

EMU_DIR="/mnt/SDCARD/Emu"
SETUP_DIR="$EMU_DIR/.emu_setup"
OVR_DIR="$SETUP_DIR/overrides"
OPT_DIR="$SETUP_DIR/options"
LAUNCH_DIR="$SETUP_DIR/launch"
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
		cp -f "$LAUNCH_DIR/standard_launch.sh" "$dir/launch.sh" && echo "copied launch.sh to $dir";
	# delete config_hidden.json if a config.json already exists to lessen chance of conflicts with system.opt
		if [ -f "$dir/config.json" ] && [ -f "$dir/config_hidden.json" ]; then
			rm -f "$dir/config_hidden.json" && echo "removed duplicate config_hidden.json from $dir"
		fi
	fi
done

# copy over unique launch scripts
cp -f "$LAUNCH_DIR/ffplay_launch.sh" "$EMU_DIR/FFPLAY/launch.sh" && echo "copied unique launch.sh to FFPLAY";
cp -f "$LAUNCH_DIR/nds_launch.sh" "$EMU_DIR/NDS/launch.sh" && echo "copied unique launch.sh to NDS";
cp -f "$LAUNCH_DIR/openbor_launch.sh" "$EMU_DIR/OPENBOR/launch.sh" && echo "copied unique launch.sh to OPENBOR";
cp -f "$LAUNCH_DIR/pico8_launch.sh" "$EMU_DIR/PICO8/launch.sh" && echo "copied unique launch.sh to PICO8";
cp -f "$LAUNCH_DIR/ports_launch.sh" "$EMU_DIR/PORTS/launch.sh" && echo "copied unique launch.sh to PORTS";
cp -f "$LAUNCH_DIR/psp_launch.sh" "$EMU_DIR/PSP/launch.sh" && echo "copied unique launch.sh to PSP";
} &> "$SETUP_DIR/log.txt"
