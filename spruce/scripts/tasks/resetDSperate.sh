#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# The live config is under XDG_CONFIG_HOME, which run_dsperate points at
# /mnt/SDCARD/Saves. Saves and states are deliberately left alone, and so is
# Emu/NDS/config -- that is DraStic's, not ours.
rm -rf /mnt/SDCARD/Saves/dsperate

if [ -d /mnt/SDCARD/Saves/dsperate ]; then
	log_message "dsperate config nuke failed?"
else
	log_message "dsperate configs have been reset."
fi
