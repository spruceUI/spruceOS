#!/bin/bash
# PORTMASTER: songo5.zip, Songo5.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$SCRIPT_DIR/songo5"

runtime="sbc_4_3_rcv12"
pck_filename="Songo5.pck"
gptk_filename="songo5.gptk"

# Logging
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ -f /mnt/SDCARD/spruce/twig ]; then
	GODOT_OPTS=${GODOT_OPTS//-f/}
    if ! glxinfo | grep "OpenGL version string"; then
		pck_filename="SongoLibmaliWarning.pck"
    fi
fi

echo "LOOKING FOR CFW_NAME ${CFW_NAME}"
export CFW_NAME
echo "LOOKING FOR DEVICE ID ${DEVICE_NAME}"
export DEVICE_NAME

# Create directory for save files
CONFDIR="$GAMEDIR/conf/"
$ESUDO mkdir -p "${CONFDIR}"

# Setup volume indicator
USE_SONGO_VOL_TCP_SERVER="1" # Set to "0" to disable the volume overlay, might need to disable for pixel 2

if [ -f /mnt/SDCARD/spruce/twig ]; then
	USE_SONGO_VOL_TCP_SERVER="0"
fi

SONGO_CFW_NAME="Spruce"

sh "${GAMEDIR}/runtime/volume-indicator/setup_vol_indicator" "${SONGO_CFW_NAME}"

export SONGO_CFW_NAME
export USE_SONGO_VOL_TCP_SERVER

# Set up brightness commands (Based on IncognitoMans approach)
export SYSFS_BL_BRIGHTNESS="$(find /sys/class/backlight/*/ -name brightness 2>/dev/null | head -n 1)"
export SYSFS_BL_COMMAND="$(find /sys/kernel/debug/dispdbg/ -name command 2>/dev/null | head -n 1)"

if [ -n "${SYSFS_BL_BRIGHTNESS}" ]; then
  echo "Backlight TYPE2 detected! setting path/type."
  export BL_TYPE="TYPE2"
  export SYSFS_BL_POWER="$(find /sys/class/backlight/*/ -name bl_power )"
  export SYSFS_BL_MAX="$(find /sys/class/backlight/*/ -name max_brightness 2>/dev/null | head -n 1)"
elif [ -n "${SYSFS_BL_COMMAND}" ]; then
  echo "Backlight TYPE1 detected! setting path/type."
  export BL_TYPE="TYPE1"
  export SYSFS_BL_NAME="$(find /sys/kernel/debug/dispdbg/ -name name 2>/dev/null | head -n 1)"
  export SYSFS_BL_PARAM="$(find /sys/kernel/debug/dispdbg/ -name param 2>/dev/null | head -n 1)"
  export SYSFS_BL_START="$(find /sys/kernel/debug/dispdbg/ -name start 2>/dev/null | head -n 1)"
  export BL_COMMAND="setbl"
  export BL_NAME="lcd0"
else
  echo "Backlight objects not found!"
  export BL_TYPE="UNKNOWN"
fi

DEFAULT_GET_BRIGHTNESS_PATH="${GAMEDIR}/runtime/brightness/default/get_brightness"
DEFAULT_SET_BRIGHTNESS_PATH="${GAMEDIR}/runtime/brightness/default/set_brightness"
SONGO_GET_BRIGHTNESS_PATH="$DEFAULT_GET_BRIGHTNESS_PATH"
SONGO_SET_BRIGHTNESS_PATH="$DEFAULT_SET_BRIGHTNESS_PATH"
NO_BRIGHT_FADE_AVAILABLE='0'

if [[ "$BL_TYPE" = "TYPE1" ]] && [[ -e "${GAMEDIR}/runtime/brightness/${SONGO_CFW_NAME}/get_brightness" ]]; then
	# Type 2 updates the stored get value when cfw adjusts brightness, so for type 1 we have to explicitly check if
	# brightness has been adjusted by the user
	SONGO_GET_BRIGHTNESS_PATH="${GAMEDIR}/runtime/brightness/${SONGO_CFW_NAME}/get_brightness"
fi

if [ "$BL_TYPE" = "UNKNOWN" ]; then
	NO_BRIGHT_FADE_AVAILABLE='1'
fi

INITIAL_BRIGHTNESS="$("$SONGO_GET_BRIGHTNESS_PATH")"

if [ -z "$INITIAL_BRIGHTNESS" ]; then
    echo "Failed to read initial brightness" >&2
    INITIAL_BRIGHTNESS=50  # fallback value if needed
fi

export SONGO_GET_BRIGHTNESS_PATH
export SONGO_SET_BRIGHTNESS_PATH
export NO_BRIGHT_FADE_AVAILABLE

cd $GAMEDIR


# Set the XDG environment variables for config & savefiles
export XDG_DATA_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

echo "XDG_DATA_HOME"
echo $XDG_DATA_HOME

export SONGO_BINARIES_DIR="$GAMEDIR/runtime"

$GPTOKEYB "$GAMEDIR/runtime/$runtime" -c "$GAMEDIR/$gptk_filename" &

# Might need to uncomment this, keep it around for now
# sleep 0.6 # For TSP only, do not move/modify this line.
# pm_platform_helper "$GAMEDIR/runtime/$runtime"

LD_LIBRARY_PATH="$GAMEDIR/runtime/ffmpeg:$LD_LIBRARY_PATH" "$GAMEDIR/runtime/$runtime" $GODOT_OPTS --main-pack "gamedata/$pck_filename"

# Clean up after app close
# Revert brightness if app crashes or brighntess ends up as zero for any reason
CURRENT_BRIGHTNESS="$("$SONGO_GET_BRIGHTNESS_PATH")"
if [ "$CURRENT_BRIGHTNESS" = "0" ]; then
    echo "Brightness is 0, restoring to $INITIAL_BRIGHTNESS"
    "$SONGO_SET_BRIGHTNESS_PATH" "$INITIAL_BRIGHTNESS"
fi

if [[ "$SONGO_CFW_NAME" != "NONE" ]]; then
	# Teardown volume indicator
	sh "${GAMEDIR}/runtime/volume-indicator/teardown_vol_indicator" "${SONGO_CFW_NAME}"
fi

# Theoretically the mount should only exist once, I use the loop on the off chance something goes horribly wrong,
# its important to be sure its unmounted or else closing the lid of the clamshell will be ignored after the app
# exit, until system restart at least

TARGET="/sys/devices/platform/hall-mh248/hallvalue"
if [ -e "$TARGET" ]; then
    while grep -q " $TARGET " /proc/mounts 2>/dev/null; do
        if umount -l "$TARGET" 2>/dev/null; then
            echo "Unmounted hallkey override: $TARGET"
        else
            echo "Failed to unmount: $TARGET"
            break
        fi
    done
fi

# Might need to add this back in
# pm_finish
