#!/bin/sh

SETUP_DIR="/mnt/SDCARD/.tmp_update/emu_setup"
OVR_DIR="$SETUP_DIR/overrides"
LAUNCH_DIR="$SETUP_DIR/launch"
CORE_DIR="$SETUP_DIR/core"
DEF_DIR="$SETUP_DIR/defaults"

EMU_DIR="/mnt/SDCARD/Emu"
{
# copy standard RA launch scripts, default.opt, and template.opt to all Emu subfolders.
for dir in $EMU_DIR/* ; do
	if [ -d $dir ]; then
		echo "dir is $dir";
		system="${dir##*/}" ;
		echo "system is $system";
		cp -f "$LAUNCH_DIR/standard_launch.sh" "$dir/launch.sh" && echo "copied launch.sh to $dir";
		cp -rf "$OVR_DIR" "$dir/" && echo "copied override template to $dir";
	# create system.opt files for each system if they don't already exist
		if [ ! -f "$dir/system.opt" ] ; then
			cp "$DEF_DIR/${system}.opt" "$dir/system.opt" && echo "created missing system.opt for $dir";
		fi
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