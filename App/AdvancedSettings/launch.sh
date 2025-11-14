#!/bin/sh

# Copy of platform detection from helperFunctions.sh
INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"sun8i"*)  export PLATFORM="A30" ;;
    *"TG5040"*) export PLATFORM="SmartPro" ;;
    *"TG3040"*) export PLATFORM="Brick" ;;
    *"0xd05"*)  export PLATFORM="Flip" ;;
esac

if [ "$PLATFORM" = "A30" ]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin"
else
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
fi

SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

# Copy of just flag_check from helperFunctions.sh here to keep launch time short
flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}" ] || [ -f "$FLAGS_DIR/${flag_name}.lock" ]; then
        return 0
    else
        return 1
    fi
}

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

# Add a mode based on which device spruce is running on
MODES="$MODES -m $PLATFORM"

if [ -f "/mnt/SDCARD/.DS_Store" ]; then
    MODES="$MODES -m Mac"
fi

[ "$PLATFORM" = "Flip" ] && echo -1 > /sys/class/miyooio_chr_dev/joy_type

if [ ! "$PLATFORM" = "A30" ]; then
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "as" -c "./as.gptk" &
	sleep 0.5
fi

cd "$BIN_PATH"
./easyConfig "$SETTINGS_PATH/settings_config" $MODES

kill -9 "$(pidof gptokeyb)" 2>/dev/null

# send signal USR1 to joystickinput to switch to ANALOG MODE
killall -q -USR1 joystickinput

# Copy spruce.cfg to www folder so the landing page can read it.
cp "$SETTINGS_PATH/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"
