#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
[ "$PLATFORM" = "SmartPro" ] && BG="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
DEF_OPT="/mnt/SDCARD/Emu/.emu_setup/defaults/${EMU_NAME}.opt"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

# try to create system option file if it doesn't exist
if [ ! -f "$SYS_OPT" ]; then
	if [ -f "$DEF_OPT" ]; then
		mkdir -p "/mnt/SDCARD/Emu/.emu_setup/options" 2>/dev/null
		cp "$DEF_OPT" "$SYS_OPT"
		log_message "core_switch.sh: created $SYS_OPT by copying  $DEF_OPT"
	else
		log_message "core_switch.sh: ERROR: no system options file nor default options file found for $EMU_NAME"
		exit 1
	fi
fi

. "$SYS_OPT"

case "$EMU_NAME" in

	"AMIGA" )
		if [ "$CORE" = "uae4arm" ]; then
			NEW_CORE="puae2021"
			NEW_DISPLAY="uae4arm-(✓PUAE2021)"

		else # current core is puae2021
			NEW_CORE="uae4arm"
			NEW_DISPLAY="(✓UAE4ARM)-puae2021"
		fi
	;;

	"ARCADE" )
		if [ "$CORE" = "fbneo" ]; then
			NEW_CORE="mame2003_plus"
			NEW_DISPLAY="fbneo-(✓MAME2003+)-fbalpha2012"

		elif [ "$CORE" = "mame2003_plus" ]; then
			NEW_CORE="fbalpha2012"
			NEW_DISPLAY="fbneo-mame2003+-(✓FBALPHA2012)"

		else # current core is fbalpha2012
			NEW_CORE="fbneo"
			NEW_DISPLAY="(✓FBNEO)-mame2003+-fbalpha2012"
		fi
	;;

	"COLECO" )
		if [ "$CORE" = "bluemsx" ]; then
			NEW_CORE="gearcoleco"
			NEW_DISPLAY="bluemsx-(✓GEARCOLECO)"

		else # current core is gearcoleco
			NEW_CORE="bluemsx"
			NEW_DISPLAY="(✓BLUEMSX)-gearcoleco"
		fi
	;;

	"CPC" )
		if [ "$CORE" = "cap32" ]; then
			NEW_CORE="crocods"
			NEW_DISPLAY="cap32-(✓CROCODS)"

		else # current core is crocods
			NEW_CORE="cap32"
			NEW_DISPLAY="(✓CAP32)-crocods"
		fi
	;;

	"CPS"* | "NEOGEO" )
		if [ "$CORE" = "fbalpha2012" ]; then
			NEW_CORE="fbneo"
			NEW_DISPLAY="fbalpha2012-(✓FBNEO)"

		else # current core is fbneo
			NEW_CORE="fbalpha2012"
			NEW_DISPLAY="(✓FBALPHA2012)-fbneo"
		fi
	;;

	"DC" )
		if [ "$CORE" = "flycast" ]; then
			NEW_CORE="flycast_xtreme"
			NEW_DISPLAY="flycast_lr-(✓FLYCAST-ALT)"

		else # current core is flycast_xtreme
			NEW_CORE="flycast"
			NEW_DISPLAY="(✓FLYCAST_LR)-flycast_alt"
		fi
	;;

	"FC" )
		if [ "$CORE" = "quicknes" ]; then
			NEW_CORE="fceumm"
			NEW_DISPLAY="(✓FCEUMM)-nestopia-quicknes"

		elif [ "$CORE" = "fceumm" ]; then
			NEW_CORE="nestopia"
			NEW_DISPLAY="fceumm-(✓NESTOPIA)-quicknes"

		else # current core is nestopia
			NEW_CORE="quicknes"
			NEW_DISPLAY="fceumm-nestopia-(✓QUICKNES)"
		fi
	;;

	"FDS" )
		if [ "$CORE" = "fceumm" ]; then
			NEW_CORE="nestopia"
			NEW_DISPLAY="fceumm-(✓NESTOPIA)"

		else # current core is nestopia
			NEW_CORE="fceumm"
			NEW_DISPLAY="(✓FCEUMM)-nestopia"
		fi
	;;

	"GB" | "GBC" )
		if [ "$CORE" = "gambatte" ]; then
			NEW_CORE="mgba"
			NEW_DISPLAY="gambatte-(✓MGBA)-tgbdual"
		elif [ "$CORE" = "mgba" ]; then
			NEW_CORE="tgbdual"
			NEW_DISPLAY="gambatte-mgba-(✓TGBDUAL)"
		else # current core is tgbdual
			NEW_CORE="gambatte"
			NEW_DISPLAY="(✓GAMBATTE)-mgba-tgbdual"
		fi
	;;

	"GBA" )
		if [ "$CORE" = "mgba" ]; then
			NEW_CORE="gpsp"
			NEW_DISPLAY="mgba-(✓GPSP)"

		else # current core is gpsp
			NEW_CORE="mgba"
			NEW_DISPLAY="(✓MGBA)-gpsp"
		fi
	;;

	"GG" | "MS" )
		if [ "$CORE" = "genesis_plus_gx" ]; then
			NEW_CORE="picodrive"
			NEW_DISPLAY="genesis+gx-(✓PICODRIVE)-gearsystem"

		elif [ "$CORE" = "picodrive" ]; then
			NEW_CORE="gearsystem"
			NEW_DISPLAY="genesis+gx-picodrive-(✓GEARSYSTEM)"

		else # current core is gearsystem
			NEW_CORE="genesis_plus_gx"
			NEW_DISPLAY="(✓GENESIS+GX)-picodrive-gearsystem"
		fi
	;;

	"LYNX" )
		if [ "$CORE" = "handy" ]; then
			NEW_CORE="mednafen_lynx"
			NEW_DISPLAY="handy-(✓MEDNAFEN)"

		else # current core is mednafen_lynx
			NEW_CORE="handy"
			NEW_DISPLAY="(✓HANDY)-mednafen"
		fi
	;;

	"MD" | "SEGACD" )
		if [ "$CORE" = "picodrive" ]; then
			NEW_CORE="genesis_plus_gx"
			NEW_DISPLAY="picodrive-(✓GENESIS+GX)"

		else # current core is genesis_plus_gx
			NEW_CORE="picodrive"
			NEW_DISPLAY="(✓PICODRIVE)-genesis+gx"
		fi
	;;

	"MSX" )
		if [ "$CORE" = "bluemsx" ]; then
			NEW_CORE="fmsx"
			NEW_DISPLAY="bluemsx-(✓FMSX)"

		else # current core is fmsx
			NEW_CORE="bluemsx"
			NEW_DISPLAY="(✓BLUEMSX)-fmsx"
		fi
	;;

	"N64" )
		if [ "$CORE" = "mupen64plus" ]; then
			NEW_CORE="km_ludicrousn64_2k22_xtreme_amped"
			NEW_DISPLAY="(✓LUDICROUSN64)-parallel-mupen64plus"

		elif [ "$CORE" = "km_ludicrousn64_2k22_xtreme_amped" ]; then
			NEW_CORE="parallel_n64"
			NEW_DISPLAY="ludicrousn64-(✓PARALLEL)-mupen64plus"

		else # current core is parallel_n64
			NEW_CORE="mupen64plus"
			NEW_DISPLAY="ludicrousn64-parallel-(✓MUPEN64PLUS)"
		fi
	;;

	"NGP"* )
		if [ "$CORE" = "mednafen_ngp" ]; then
			NEW_CORE="race"
			NEW_DISPLAY="mednafen-(✓RACE)"

		else # current core is race
			NEW_CORE="mednafen_ngp"
			NEW_DISPLAY="(✓MEDNAFEN)-race"
		fi
	;;

	"PS" )
		if [ "$CORE" = "km_duckswanstation_xtreme_amped" ]; then
			NEW_CORE="pcsx_rearmed"
			NEW_DISPLAY="(✓PCSX_REARMED)-duckswanstation"

		else # current core is pcsx_rearmed
			NEW_CORE="km_duckswanstation_xtreme_amped"
			NEW_DISPLAY="pcsx_rearmed-(✓DUCKSWANSTATION)"
		fi
	;;

	"SATURN" )
		if [ "$CORE" = "sa_bios" ]; then
			NEW_CORE="sa_hle"
			NEW_DISPLAY="libretro-sa_bios-(✓SA_HLE)"

		elif [ "$CORE" = "sa_hle" ]; then
			NEW_CORE="yabasanshiro"
			NEW_DISPLAY="(✓LIBRETRO)-sa_bios-sa_hle"

		else # current core is yabasanshiro (libretro)
			NEW_CORE="sa_bios"
			NEW_DISPLAY="libretro-(✓SA_BIOS)-sa_hle"
		fi
	;;

	"SEGASGONE" )
		if [ "$CORE" = "genesis_plus_gx" ]; then
			NEW_CORE="bluemsx"
			NEW_DISPLAY="genesis+gx-(✓BLUEMSX)-gearsystem"

		elif [ "$CORE" = "bluemsx" ]; then
			NEW_CORE="gearsystem"
			NEW_DISPLAY="genesis+gx-bluemsx-(✓GEARSYSTEM)"

		else # current core is gearsystem
			NEW_CORE="genesis_plus_gx"
			NEW_DISPLAY="(✓GENESIS+GX)-bluemsx-gearsystem"
		fi
	;;

	"SFC" )
		if [ "$CORE" = "chimerasnes" ]; then
			NEW_CORE="mednafen_supafaust"
			NEW_DISPLAY="chimerasnes-(✓SUPAFAUST)-snes9x"

		elif [ "$CORE" = "mednafen_supafaust" ]; then
			NEW_CORE="snes9x"
			NEW_DISPLAY="chimerasnes-supafaust-(✓SNES9X)"

		else # current core is snes9x
			NEW_CORE="chimerasnes"
			NEW_DISPLAY="(✓CHIMERASNES)-supafaust-snes9x"
		fi
	;;

	* )
		log_message "core_switch.sh: ERROR: no core switch logic in place for $EMU_NAME"
		exit 1
	;;
esac

log_message "core_switch.sh: changing core for $EMU_NAME from $CORE to $NEW_CORE"

display -i "$BG" -t "Core changed to $NEW_CORE"

sed -i "s|\"Emu Core:.*\"|\"Emu Core: $NEW_DISPLAY\"|g" "$CONFIG"
sed -i "s|CORE=.*|CORE=\"$NEW_CORE\"|g" "$SYS_OPT"

sleep 2
display_kill
