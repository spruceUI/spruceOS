#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
[ "$PLATFORM" = "SmartPro" ] && BG="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
DEF_OPT="/mnt/SDCARD/Emu/.emu_setup/defaults/${EMU_NAME}.opt"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"
CUSTOM_DEF_OPT="/mnt/SDCARD/Emu/${EMU_NAME}/default.opt"

# try to create system option file if it doesn't exist
if [ ! -f "$SYS_OPT" ]; then
	if [ -f "$DEF_OPT" ]; then
		mkdir -p "/mnt/SDCARD/Emu/.emu_setup/options" 2>/dev/null
		cp "$DEF_OPT" "$SYS_OPT"
		log_message "cpu_switch.sh: created $SYS_OPT by copying  $DEF_OPT"
	elif [ -f "$CUSTOM_DEF_OPT" ]; then
		mkdir -p "/mnt/SDCARD/Emu/.emu_setup/options" 2>/dev/null
		cp "$CUSTOM_DEF_OPT" "$SYS_OPT"
		log_message "cpu_switch.sh: created $SYS_OPT by copying $CUSTOM_DEF_OPT"
	else
		log_message "cpu_switch.sh: ERROR: no system options file nor default options file found for $EMU_NAME"
		exit 1
	fi
fi

. "$SYS_OPT"

case "$EMU_NAME" in

	"DC" | "SATURN" )
		if [ "$MODE" = "performance" ]; then
			NEW_MODE="overclock"
			NEW_DISPLAY="Perf-(✓MAX)"

		else # current mode is overclock
			NEW_MODE="performance"
			NEW_DISPLAY="(✓PERF)-Max"
		fi
	;;

	*)
		if [ "$MODE" = "smart" ]; then
			NEW_MODE="performance"
			NEW_DISPLAY="Smart-(✓PERF)-Max"

		elif [ "$MODE" = "performance" ]; then
			NEW_MODE="overclock"
			NEW_DISPLAY="Smart-Perf-(✓MAX)"

		else # current mode is overclock
			NEW_MODE="smart"
			NEW_DISPLAY="(✓SMART)-Perf-Max"
		fi
	;;

esac

log_message "cpu_switch.sh: changing cpu mode for $EMU_NAME from $MODE to $NEW_MODE"

display -i "$BG" -t "CPU Mode changed to $NEW_MODE"

sed -i "s|\"CPU:.*\"|\"CPU: $NEW_DISPLAY\"|g" "$CONFIG"
sed -i "s|MODE=.*|MODE=\"$NEW_MODE\"|g" "$SYS_OPT"

sleep 2
display_kill
