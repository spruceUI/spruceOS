#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

###### PARSE THE JSON #####

json_file="$2"

file="$(jq -r '.file' "$json_file")"
system="$(jq -r '.system' "$json_file")"
description="$(jq -r '.description' "$json_file")"
requires_files="$(jq -r '.requires_files' "$json_file")"
# version="$(jq -r '.version' "$json_file")"

# add notice that additional files are needed
if [ "$requires_files" = "true" ]; then
	description="$description Requires additional files."
fi

##### MAIN EXECUTION #####

if [ "$1" = "run" ]; then
	if [ -f "/mnt/SDCARD/Roms/$system/$file" ]; then
		echo -n "✓ Will be reinstalled."
		return 0
	else
		echo -n "✓ Will be installed."
		return 0
	fi
else
	if [ -f "/mnt/SDCARD/Roms/$system/$file" ]; then
		echo -n "Already installed!"
		return 0
	else
		echo -n "$description"
		return 0
	fi
fi