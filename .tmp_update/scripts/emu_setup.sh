#!/bin/sh

SETUP_DIR="/mnt/SDCARD/.tmp_update/emu_setup"
SPD_DIR="$SETUP_DIR/speed"
OVR_DIR="$SETUP_DIR/overrides"
LAUNCH_DIR="$SETUP_DIR/launch"
CORE_DIR="$SETUP_DIR/core"

EMU_DIR="/mnt/SDCARD/Emu"

# copy standard RA launch scripts, template.opt, and cpu speed scripts to all Emu subfolders.
for dir in $EMU_DIR/*; do
	if [ -d $dir ]; then
		cp -f "$LAUNCH_DIR/standard_launch.sh" "$dir/launch.sh"
		cp -rf -t "$dir/" "$OVR_DIR" "$SPD_DIR/648.sh" "$SPD_DIR/816.sh" "$SPD_DIR/1200.sh" "$SPD_DIR/1344.sh" "$SPD_DIR/1512.sh"
	fi
done

# copy over unique launch scripts
cp -f "$LAUNCH_DIR/ffplay_launch.sh" "$EMU_DIR/FFPLAY/launch.sh"
cp -f "$LAUNCH_DIR/nds_launch.sh" "$EMU_DIR/NDS/launch.sh"
cp -f "$LAUNCH_DIR/openbor_launch.sh" "$EMU_DIR/OPENBOR/launch.sh"
cp -f "$LAUNCH_DIR/pico8_launch.sh" "$EMU_DIR/PICO8/launch.sh"
cp -f "$LAUNCH_DIR/ports_launch.sh" "$EMU_DIR/PORTS/launch.sh"
cp -f "$LAUNCH_DIR/psp_launch.sh" "$EMU_DIR/PSP/launch.sh"


#todo: figure out best way to consolidate core scripts for systems that have different core options from one another.
