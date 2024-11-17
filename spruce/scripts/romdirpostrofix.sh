#!/bin/sh

# This script searches the Roms folder for directories whose names have
# one or more apostrophes in them, and removes those apostrophes, allowing
# MainUI to see them.

ROMS_DIR="/mnt/SDCARD/Roms"

for SYSTEM in "$ROMS_DIR"/*; do
	if [ -d "$SYSTEM" ]; then
		for FILENAME in "$SYSTEM"/*; do
			if [ -d "$FILENAME" ]; then
				case "$FILENAME" in
					*\'*)
						NEW_FILENAME="${FILENAME//\'/}"
						mv "$FILENAME" "$NEW_FILENAME"
					;;
				esac
			fi
		done
	fi
done