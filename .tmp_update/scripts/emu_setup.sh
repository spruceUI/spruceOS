#!/bin/sh

SETUP_DIR="/mnt/SDCARD/.tmp_update/emu_setup"
SPD_DIR="$SETUP_DIR/speed"
OVR_DIR="$SETUP_DIR/overrides"
LAUNCH_DIR="$SETUP_DIR/launch"
CORE_DIR="$SETUP_DIR/core"
DEF_DIR="$SETUP_DIR/defaults"

EMU_DIR="/mnt/SDCARD/Emu"

# copy standard RA launch scripts, default.opt, template.opt, and cpu speed scripts to all Emu subfolders.
for dir in $EMU_DIR/*; do
	if [ -d $dir ]; then
		cp -f "$LAUNCH_DIR/standard_launch.sh" "$dir/launch.sh"
		cp -rf "$OVR_DIR" "$dir/" 
		cp -f "$SPD_DIR"/* "$dir"
		cp -f "$DEF_DIR/${basename "$dir"}.opt" "$dir/default.opt"
	# create system.opt files for each system if they don't already exist
		if [ ! -f "$dir/system.opt" ] ; then
			cp "$dir/default.opt" "$dir/system.opt"		
		fi
	fi
done

# copy over unique launch scripts
cp -f "$LAUNCH_DIR/ffplay_launch.sh" "$EMU_DIR/FFPLAY/launch.sh"
cp -f "$LAUNCH_DIR/nds_launch.sh" "$EMU_DIR/NDS/launch.sh"
cp -f "$LAUNCH_DIR/openbor_launch.sh" "$EMU_DIR/OPENBOR/launch.sh"
cp -f "$LAUNCH_DIR/pico8_launch.sh" "$EMU_DIR/PICO8/launch.sh"
cp -f "$LAUNCH_DIR/ports_launch.sh" "$EMU_DIR/PORTS/launch.sh"
cp -f "$LAUNCH_DIR/psp_launch.sh" "$EMU_DIR/PSP/launch.sh"

# copy over core switch scripts to appropriate Emu subfolders
cd "$CORE_DIR"
for script in "fbneo.sh" "fbalpha2012.sh" "mame2003_plus.sh" "mame2003_xtreme.sh"; do
	cp "$script" "$EMU_DIR/ARCADE/"
done

for script in "fbneo.sh" "fbalpha2012_cps1.sh"; do
	cp "$script" "$EMU_DIR/CPS1/"
done

for script in "fbneo.sh" "fbalpha2012_cps2.sh"; do
	cp "$script" "$EMU_DIR/CPS2/"
done

for script in "fbneo.sh" "fbalpha2012_cps3.sh"; do
	cp "$script" "$EMU_DIR/CPS3/"
done

for script in "fbneo.sh" "fbalpha2012_neogeo.sh"; do
	cp "$script" "$EMU_DIR/NEOGEO/"
done

for script in "puae.sh" "puae2021.sh" "uae4arm.sh"; do
	cp "$script" "$EMU_DIR/AMIGA/"
done

for script in "crocods.sh" "cap32.sh"; do
	cp "$script" "$EMU_DIR/CPC"
done

for script in "fceumm.sh" "nestopia"; do
	cp "$script" "$EMU_DIR/FC/"
done

for script in "gambatte.sh" "mgba.sh"; do
	cp "$script" "$EMU_DIR/GB/"
	cp "$script" "$EMU_DIR/GBC/"
done

for script in "gpsp.sh" "mgba.sh"; do
	cp "$script" "$EMU_DIR/GBA/"
done

for script in "gearsystem.sh" "genesis_plus_gx.sh" "picodrive.sh"; do
	cp "$script" "$EMU_DIR/GG/"
	cp "$script" "$EMU_DIR/MS/"
done

for script in "genesis_plus_gx.sh" "picodrive.sh"; do
	cp "$script" "$EMU_DIR/MD/"
	cp "$script" "$EMU_DIR/SEGACD/"
done

for script in "handy.sh" "mednafen_lynx.sh"; do
	cp "$script" "$EMU_DIR/LYNX/"
done


for script in "race.sh" "mednafen_ngp.sh"; do
	cp "$script" "$EMU_DIR/NGP/"
	cp "$script" "$EMU_DIR/NGPC/"
done

for script in "snes9x.sh" "snes9x2005.sh" "mednafen_supafaust.sh"; do
	cp "$script" "$EMU_DIR/NEOGEO/"
done
