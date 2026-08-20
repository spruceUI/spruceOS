#!/bin/bash
# PORTMASTER: songo5.zip, Songo5.sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_smart

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$SCRIPT_DIR/songo5"

runtime="sbc_4_3_rcv12"
pck_filename="Songo5.pck"
#gptk_filename="songo5.gptk"

# Logging
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ -f /mnt/SDCARD/spruce/twig ]; then
	GODOT_OPTS=${GODOT_OPTS//-f/}
    if ! glxinfo | grep "OpenGL version string"; then
		pck_filename="SongoLibmaliWarning.pck"
    fi
fi


# Theoretically the mount should only exist once, the loop is on the off chance
# something goes horribly wrong. Its important to be sure its unmounted or else
# closing the lid of the clamshell will be ignored after the app exit, until
# system restart at least.
#
# The first node is the Flip's. The XX clamshells expose the lid somewhere else
# entirely - see device_lid_open in AnbernicXXCommon.sh - so check both.
unmount_hall_overrides() {
    local TARGET MOUNTED
    for TARGET in /sys/devices/platform/hall-mh248/hallvalue \
                  /sys/class/power_supply/axp2202-battery/hallkey; do
        [ -e "$TARGET" ] || continue

        # /proc/mounts records the canonical path, not the one that was mounted.
        # The XX node is reached through a /sys/class symlink, so the mount shows
        # up as /sys/devices/platform/soc/twi5/.../hallkey and a literal
        # comparison never matched - the override stayed mounted until the next
        # reboot, which is precisely the state this exists to prevent.
        MOUNTED="$(readlink -f "$TARGET" 2>/dev/null || echo "$TARGET")"

        while grep -q " $MOUNTED " /proc/mounts 2>/dev/null; do
            if umount -l "$TARGET" 2>/dev/null; then
                echo "Unmounted hallkey override: $TARGET"
            else
                echo "Failed to unmount: $TARGET"
                break
            fi
        done
    done
}

# Songo suppresses the lid itself by bind-mounting runtime/hall_override/hallkey
# - a file containing "1", meaning open - over the hall sensor node, so anything
# polling the lid keeps seeing it open while music plays. On the XX line that
# never takes effect: the app logs its override source as "/hall_override/hallkey",
# having resolved the directory prefix to nothing, so the mount source does not
# exist. spruce's lid_watchdog_v2.sh then reads the real sensor and suspends
# mid-song.
#
# Do it here instead, for the whole session. Killing the watchdog is not an
# alternative: launch_startup_watchdogs runs once from runtime.sh before the main
# loop rather than on each return to the menu, so a killed lid watchdog would
# stay dead until reboot.
#
# Scoped to Anbernic deliberately. The same prefix bug presumably affects the
# Flip, but that device works today and this is not the session to find out
# otherwise.
# The override is staged in /tmp rather than mounted straight out of the app
# folder, because BusyBox mount truncates a source path at the first "#" - and
# this app is installed in a directory called "Songo#5". It reports
#   mounting /mnt/SDCARD/App/Songo on ... failed: No such file or directory
# which reads like a missing file rather than a mangled argument. The same mount
# from a hash-free path succeeds. This is the likeliest reason Songo's own
# suppression never took effect here either.
XX_HALL_NODE="/sys/class/power_supply/axp2202-battery/hallkey"
XX_HALL_SRC="/tmp/songo_hall_override"
case "$PLATFORM" in
    "Anbernic"*)
        if [ -e "$XX_HALL_NODE" ] && [ -f "$GAMEDIR/runtime/hall_override/hallkey" ]; then
            # Clear anything a previous crash left behind before stacking a new one
            unmount_hall_overrides
            cp "$GAMEDIR/runtime/hall_override/hallkey" "$XX_HALL_SRC" 2>/dev/null
            if mount -o bind "$XX_HALL_SRC" "$XX_HALL_NODE" 2>/dev/null; then
                echo "Lid suppressed for this session: $XX_HALL_NODE"
                trap 'unmount_hall_overrides' INT TERM
            else
                echo "Could not suppress lid: bind mount failed"
            fi
        fi
        ;;
esac

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

# The XX line is TYPE1 but takes the default getter, not the spruce one: the
# spruce getter needs either DEVICE_BRIGHTNESS_PATH, which AnbernicXXCommon.cfg
# leaves empty, or current_backlight(), which no Anbernic device_functions file
# defines - so there it would fail through to a hard-coded 155. The default
# getter reads /sys/class/disp, which on these devices is live, so the
# staleness the spruce getter exists to work around does not apply.
if [[ "$PLATFORM" != Anbernic* ]] && [[ "$BL_TYPE" = "TYPE1" ]] && [[ -e "${GAMEDIR}/runtime/brightness/${SONGO_CFW_NAME}/get_brightness" ]]; then
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
# $sdl_controllerconfig is a PortMaster variable and is empty under spruce, so
# on most devices this exports nothing and SDL falls back to its built-in
# mapping database. The Anbernic XX line is not in that database: every H700
# model reports the same GUID under the name "ANBERNIC-keys", so without a
# mapping the runtime sees an unrecognised joystick and no button does anything.
# AnbernicXXCommon.cfg carries the map and export_sdl_gamecontroller_map
# publishes it.
#
# Positional, matching Gallery, PixelReader and FileManagement. The map in the
# cfg is label-named - "a" is the button silk-screened A, which on these
# Nintendo-layout pads is the East one - while SDL's own vocabulary, which this
# runtime speaks, puts "a" on the South button. Without the swap every binding
# lands one button over.
case "$PLATFORM" in
    "Anbernic"*)
        export_sdl_gamecontroller_map positional
        ;;
    *)
        export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
        ;;
esac

echo "XDG_DATA_HOME"
echo $XDG_DATA_HOME

export SONGO_BINARIES_DIR="$GAMEDIR/runtime"
export SONGO_DIR_TIP="On Spruce I suggest making a MUSIC folder in /mnt/SDCARD/"

#$GPTOKEYB "$GAMEDIR/runtime/$runtime" -c "$GAMEDIR/$gptk_filename" &

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

unmount_hall_overrides

# Might need to add this back in
# pm_finish
