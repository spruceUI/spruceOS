#!/bin/sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
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

# send signal USR2 to joystickinput to switch to KEYBOARD MODE
# this allows joystick to be used as DPAD in setting app
killall -q -USR2 joystickinput

# Initialize empty string for modes
MODES=""

# Add modes based on flag checks
if flag_check "developer_mode"; then
    MODES="$MODES -m Developer"
fi

if flag_check "designer_mode"; then
    MODES="$MODES -m Designer"
fi

PICO_DIR="/mnt/SDCARD/Emu/PICO8/bin/"
if [ -f "$PICO_DIR/pico8.dat" ] && [ -f "$PICO_DIR/pico8_dyn" ]; then
    MODES="$MODES -m Pico"
fi

if flag_check "simple_mode"; then
    MODES="$MODES -m Simple"
else
    MODES="$MODES -m Not_simple"
fi

if [ "$($HELPER_PATH check expert_settings)" = "on" ] && ! flag_check "simple_mode"; then
    MODES="$MODES -m Expert"
fi

if [ -f "/mnt/SDCARD/.DS_Store" ]; then MODES="$MODES -m Mac"; fi # will mac always create a junk file at the sdcard root?

# Easy to add more modes like this:
# if flag_check "some_other_mode"; then
#     MODES="$MODES -m other_mode"
# fi

cd $BIN_PATH
./easyConfig $SETTINGS_PATH/settings_config $MODES

# send signal USR1 to joystickinput to switch to ANALOG MODE
killall -q -USR1 joystickinput

auto_regen_tmp_update
# Copy spruce.cfg to www folder so the landing page can read it.
cp "$SETTINGS_PATH/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"