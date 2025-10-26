#!/bin/sh

if [ "$PLATFORM" = "A30" ]; then
  BIN_PATH="/mnt/SDCARD/spruce/bin"
else
  BIN_PATH="/mnt/SDCARD/spruce/bin64"
fi
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

HELPER_PATH="/mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh"

# Copy of flag_check in helperFunctions.sh
# Here to keep launch time short
flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}" ] || [ -f "$FLAGS_DIR/${flag_name}.lock" ]; then
        return 0
    else
        return 1
    fi
}

# Copy of platform detection from helperFunctions.sh
# Detect device and export to any script sourcing helperFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)

case $INFO in
*"sun8i"*)
	export PLATFORM="A30"
    ;;
*"TG5040"*)
	export PLATFORM="SmartPro"
	;;
*"TG3040"*)
	export PLATFORM="Brick"
	;;
*"0xd05"*)
    export PLATFORM="Flip"
    ;;
*)
    export PLATFORM="A30"
    ;;
esac

# send signal USR2 to joystickinput to switch to KEYBOARD MODE
# this allows joystick to be used as DPAD in setting app
killall -q -USR2 joystickinput

# Initialize empty string for modes
MODES=""

# Add modes based on flag checks
if flag_check "developer_mode"; then
    MODES="$MODES -m Developer"
fi

PICO_DIR="/mnt/SDCARD/Emu/PICO8/bin"
BIOS_DIR="/mnt/SDCARD/BIOS"
if [ -f "$PICO_DIR/pico8.dat" ] || [ -f "$BIOS_DIR/pico8.dat" ]; then
    MODES="$MODES -m Pico"
fi

if flag_check "simple_mode"; then
    MODES="$MODES -m Simple"
else
    MODES="$MODES -m Not_simple"
fi

# Add a mode based on which device spruce is running on
MODES="$MODES -m $PLATFORM"

if [ -f "/mnt/SDCARD/.DS_Store" ]; then MODES="$MODES -m Mac"; fi # will mac always create a junk file at the sdcard root?

# Easy to add more modes like this:
# if flag_check "some_other_mode"; then
#     MODES="$MODES -m other_mode"
# fi

[ "$PLATFORM" = "Flip" ] && echo -1 > /sys/class/miyooio_chr_dev/joy_type

if [ ! "$PLATFORM" = "A30" ]; then
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "as" -c "./as.gptk" &
	sleep 0.5
fi

cd $BIN_PATH
./easyConfig $SETTINGS_PATH/settings_config $MODES

kill -9 "$(pidof gptokeyb)"

# send signal USR1 to joystickinput to switch to ANALOG MODE
killall -q -USR1 joystickinput

# bring this back if we ever decide to import helperFunctions.sh
# auto_regen_tmp_update
# Copy spruce.cfg to www folder so the landing page can read it.
cp "$SETTINGS_PATH/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"
