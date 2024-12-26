#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
DEF_OPT="/mnt/SDCARD/Emu/.emu_setup/defaults/${EMU_NAME}.opt"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

# try to create system option file if it doesn't exist
if [ ! -f "$SYS_OPT" ]; then
	if [ -f "$DEF_OPT" ]; then
		mkdir -p "/mnt/SDCARD/Emu/.emu_setup/options" 2>/dev/null
		cp "$DEF_OPT" "$SYS_OPT"
		log_message "cpu_switch.sh: created $SYS_OPT by copying  $DEF_OPT"
	else
		log_message "cpu_switch.sh: ERROR: no system options file nor default options file found for $EMU_NAME"
		exit 1
	fi
fi

. "$SYS_OPT"

case "$EMU_NAME" in

	"DC" | "N64" )
		if [ "$MODE" = "performance" ]; then
			NEW_MODE="overclock"
			NEW_DISPLAY="Performance-(✓OVERCLOCK)"

		else # current mode is overclock
			NEW_MODE="performance"
			NEW_DISPLAY="(✓PERFORMANCE)-Overclock"
		fi
	;;

	*)
		if [ "$MODE" = "smart" ]; then
			NEW_MODE="performance"
			NEW_DISPLAY="Smart-(✓PERFORMANCE)-Overclock"

		elif [ "$MODE" = "performance" ]; then
			NEW_MODE="overclock"
			NEW_DISPLAY="Smart-Performance-(✓OVERCLOCK)"

		else # current mode is overclock
			NEW_MODE="smart"
			NEW_DISPLAY="(✓SMART)-Performance-Overclock"
		fi
	;;

esac

log_message "cpu_switch.sh: changing cpu mode for $EMU_NAME from $MODE to $NEW_MODE"

display -i "$BG" -t "CPU Mode changed to $NEW_MODE"

sed -i "s|\"Emu Core:.*\"|\"Emu Core: $NEW_DISPLAY\"|g" "$CONFIG"
sed -i "s|MODE=.*|MODE=\"$NEW_MODE\"|g" "$SYS_OPT"

sleep 2
display_kill
