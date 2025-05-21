#!/bin/sh

# This "launch script" just creates a flag to be picked up
# by principal.sh to know to launch the actual BitPal script.
#
# By doing it this way, BitPal gets executed outside of the
# cmd_to_run.sh logic, which makes it more convenient for Bitpal
# itself to launch games via cmd_to_run.sh.

touch /mnt/SDCARD/spruce/flags/bitpal.lock