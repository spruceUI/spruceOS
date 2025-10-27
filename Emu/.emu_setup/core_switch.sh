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

	"DC" )
		if [ "$CORE" = "flycast" ]; then
			NEW_CORE="flycast_xtreme"
			NEW_DISPLAY="flycast_lr-(✓FLYCAST-ALT)"

		else # current core is flycast_xtreme
			NEW_CORE="flycast"
			NEW_DISPLAY="(✓FLYCAST_LR)-flycast_alt"
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

	"NDS" )
		if [ "$CORE" = "drastic_trngaje" ]; then
			NEW_CORE="drastic_steward"
			NEW_DISPLAY="trngaje-(✓STEWARD)-original"
		
		elif [ "$CORE" = "drastic_steward" ]; then
			NEW_CORE="drastic_original"
			NEW_DISPLAY="trngaje-steward-(✓ORIGINAL)"

		else # current core is drastic_original
			NEW_CORE="drastic_trngaje"
			NEW_DISPLAY="(✓TRNGAJE)-steward-original"
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
