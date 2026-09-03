#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# The live config is under XDG_CONFIG_HOME, which run_dsperate points at
# /mnt/SDCARD/Saves. Emu/NDS/config is where it used to live, so clear that too
# or an upgraded card keeps a stale copy nobody reads. Saves and states are
# deliberately left alone.
rm -rf /mnt/SDCARD/Saves/dsperate /mnt/SDCARD/Emu/NDS/config

if [ -d /mnt/SDCARD/Saves/dsperate ]; then
	log_message "dsperate config nuke failed?"
else
	log_message "dsperate configs have been reset."
fi
