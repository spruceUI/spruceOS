#!/bin/sh

SETUP_DIR="/mnt/SDCARD/.tmp_update/emu_setup"
SPD_DIR="$SETUP_DIR/speed"
OVR_DIR="$SETUP_DIR/overrides"
LAUNCH_DIR="$SETUP_DIR/launch"
CORE_DIR="$SETUP_DIR/core"
DEF_DIR="$SETUP_DIR/defaults"

EMU_DIR="/mnt/SDCARD/Emu"
{
# remove config.json and system.opt versions with standalone CPS1/2/3/Neogeo cores
for dir in "$EMU_DIR/CPS1" "$EMU_DIR/CPS2" "$EMU_DIR/CPS3" "$EMU_DIR/NEOGEO" ; do
	if [ -f "$dir/config.json" ] && [ -f "$dir/config_hidden.json" ]; then
		rm -f "$dir/system.opt" && echo "removed old version of system.opt from $dir"
		rm -f "$dir/config.json" && echo "removed old version of config.json from $dir"
	fi
done

# fix config.json for SFC for users who had it set up pre-chimerasnes default
if [ -f "$EMU_DIR/SFC/system.opt" ]; then
	if ! grep -q "CORE=\"chimerasnes\"" "$EMU_DIR/SFC/system.opt" ; then
		. $EMU_DIR/SFC/system.opt && echo "SFC core is ${CORE}"
		cd "$EMU_DIR/SFC"
		sh "$EMU_DIR/SFC/${CORE}.sh" && echo "executed ${CORE}.sh"
	fi
fi

# copy standard RA launch scripts, default.opt, template.opt, and cpu speed scripts to all Emu subfolders.
for dir in $EMU_DIR/* ; do
	if [ -d $dir ]; then
		echo "dir is $dir";
		system="${dir##*/}" ;
		echo "system is $system";
		cp -f "$LAUNCH_DIR/standard_launch.sh" "$dir/launch.sh" && echo "copied launch.sh to $dir";
		cp -rf "$OVR_DIR" "$dir/" && echo "copied override template to $dir";
		cp -f "$SPD_DIR"/* "$dir/" && echo "copied cpu speed scripts to $dir";
		cp -f "$DEF_DIR/${system}.opt" "$dir/default.opt" && echo "copied default.opt to $dir";
	# create system.opt files for each system if they don't already exist
		if [ ! -f "$dir/system.opt" ] ; then
			cp "$dir/default.opt" "$dir/system.opt"	&& echo "created missing system.opt for $dir";
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

# copy over core switch scripts to appropriate Emu subfolders
cd "$CORE_DIR"
for script in "fbneo.sh" "fbalpha2012.sh" "mame2003_plus.sh" "mame2003_xtreme.sh"; do
	cp -f "$script" "$EMU_DIR/ARCADE/";
done

for script in "fbneo.sh" "fbalpha2012.sh"; do
	cp -f "$script" "$EMU_DIR/CPS1/" && echo "copied $script to CPS1";
	cp -f "$script" "$EMU_DIR/CPS2/" && echo "copied $script to CPS2";
	cp -f "$script" "$EMU_DIR/CPS3/" && echo "copied $script to CPS3";
	cp -f "$script" "$EMU_DIR/NEOGEO/" && echo "copied $script to NEOGEO";
done

for script in "puae.sh" "puae2021.sh" "uae4arm.sh"; do
	cp -f "$script" "$EMU_DIR/AMIGA/" && echo "copied $script to AMIGA";
done

for script in "crocods.sh" "cap32.sh"; do
	cp -f "$script" "$EMU_DIR/CPC" && echo "copied $script to CPC";
done

for script in "fceumm.sh" "nestopia.sh"; do
	cp -f "$script" "$EMU_DIR/FC/" && echo "copied $script to FC";
done

for script in "gambatte.sh" "mgba.sh"; do
	cp -f "$script" "$EMU_DIR/GB/" && echo "copied $script to GB";
	cp -f "$script" "$EMU_DIR/GBC/" && echo "copied $script to GBC";
done

for script in "gpsp.sh" "mgba.sh"; do
	cp -f "$script" "$EMU_DIR/GBA/" && echo "copied $script to GBA";
done

for script in "gearsystem.sh" "genesis_plus_gx.sh" "picodrive.sh"; do
	cp -f "$script" "$EMU_DIR/GG/" && echo "copied $script to GG";
	cp -f "$script" "$EMU_DIR/MS/" && echo "copied $script to MS";
done

for script in "genesis_plus_gx.sh" "picodrive.sh"; do
	cp -f "$script" "$EMU_DIR/MD/" && echo "copied $script to MD";
	cp -f "$script" "$EMU_DIR/SEGACD/" && echo "copied $script to SEGACD";
done

for script in "handy.sh" "mednafen_lynx.sh"; do
	cp -f "$script" "$EMU_DIR/LYNX/" && echo "copied $script to LYNX";
done


for script in "race.sh" "mednafen_ngp.sh"; do
	cp -f "$script" "$EMU_DIR/NGP/" && echo "copied $script to NGP";
	cp -f "$script" "$EMU_DIR/NGPC/" && echo "copied $script to NGPC";
done

for script in "snes9x.sh" "snes9x2005.sh" "mednafen_supafaust.sh" "chimerasnes.sh"; do
	cp -f "$script" "$EMU_DIR/SFC/" && echo "copied $script to SFC";
done
} &> "$SETUP_DIR/log.txt"
