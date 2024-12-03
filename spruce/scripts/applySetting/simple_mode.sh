#!/bin/sh

ARGUMENT="$1"

if [ $ARGUMENT = "apply"]; then

	# remove all X button menu items except aleatorio.sh
	cd /mnt/SDCARD/Emu
	for dir in ./*; do
		if [ -f "${dir}/config.json" ] && [ -f "${dir}/config.json.simple"]; then
			mv "${dir}/config.json" "${dir}/config.json.original"
			cp -f "${dir}/config.json.simple" "${dir}/config.json"
		fi
	done

else # ARGUMENT is remove

	# re-enable X menu items
	cd /mnt/SDCARD/Emu
	for dir in ./*; do
		if [ -f "${dir}/config.json.original" ]; then
			[ -f "${dir}/config.json" ] && rm -f "${dir}/config.json"
			mv "${dir}/config.json.original" "${dir}/config.json"
		fi
	done

fi