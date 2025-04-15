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
		log_message "control_switch.sh: created $SYS_OPT by copying  $DEF_OPT"
	elif [ -f "$CUSTOM_DEF_OPT" ]; then
		mkdir -p "/mnt/SDCARD/Emu/.emu_setup/options" 2>/dev/null
		cp "$CUSTOM_DEF_OPT" "$SYS_OPT"
		log_message "control_switch.sh: created $SYS_OPT by copying $CUSTOM_DEF_OPT"
	else
		log_message "control_switch.sh: ERROR: no system options file nor default options file found for $EMU_NAME"
		exit 1
	fi
fi

if ! grep 'PORT_CONTROL=' "$SYS_OPT"; then
  echo "PORT_CONTROL not found in $SYS_OPT"
  echo "export PORT_CONTROL=\"X360\"" >> "$SYS_OPT"

fi

. "$SYS_OPT"

echo "Current PORT_CONTROL value is $PORT_CONTROL"

if [ "$PORT_CONTROL" = "X360" ]; then
	NEW_CONTROL="Nintendo"
	NEW_DISPLAY="X360-(✓Nintendo)"
	echo "Changing to Nintendo"
else 
	NEW_CONTROL="X360"
	NEW_DISPLAY="(✓X360)-Nintendo"
	echo "Changing to X360"
fi

sed -i "s|\"Controls:.*\"|\"Controls: $NEW_DISPLAY\"|g" "$CONFIG"
sed -i "s|PORT_CONTROL=.*|PORT_CONTROL=\"$NEW_CONTROL\"|g" "$SYS_OPT"

log_message "control_switch.sh: changing control mode for $EMU_NAME from $MODE to $NEW_CONTROL"

display -i "$BG" -t "Port Control Mode changed to $NEW_CONTROL"


sleep 2
display_kill
