#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# check flag to avoid reenter
if flag_check "emufresh"; then
	return 0
fi

# setup flag to avoid reenter
flag_add "emufresh"

emu_path="/mnt/SDCARD/Emu"
roms_path="/mnt/SDCARD/Roms"
roms2_path="/media/sdcard1/Roms"
md5_path="/mnt/SDCARD/Emu/.emu_setup/md5"

log_message "emufresh: checking if emufresh required"

# ensure md5 folder exists
mkdir -p "$md5_path"

# handle clear all option
if [ "$1" = "-clearall" ]; then
	# remove all md5 files
	rm -r "$md5_path" && log_message "emufresh: removed $md5_path and its contents"

	# hide all systems
	find "$roms_path" -mindepth 1 -maxdepth 1 -type d | while read -r folder; do
		system_name=$(basename "$folder")
		config_file="$emu_path/$system_name/config.json"
		sed -i 's/^{*$/{{/' "$config_file"
	done
	if [ -d "$roms2_path" ]; then
		find "$roms2_path" -mindepth 1 -maxdepth 1 -type d | while read -r folder; do
			system_name=$(basename "$folder")
			config_file="$emu_path/$system_name/config.json"
			sed -i 's/^{*$/{{/' "$config_file"
		done
	fi
	log_message "emufresh: hid all systems by breaking their config.json"

	# kill MainUI
	killall -9 MainUI

	# remove flag before exit
	flag_remove "emufresh"

	# exit with 0
	exit 0
fi

# handle show all option
if [ "$1" = "-showall" ]; then
	# show all systems
	find "$roms_path" -mindepth 1 -maxdepth 1 -type d | while read -r folder; do
		system_name=$(basename "$folder")
		config_file="$emu_path/$system_name/config.json"
		sed -i 's/^{{*$/{/' "$config_file"
	done
	if [ -d "$roms2_path" ]; then
		find "$roms2_path" -mindepth 1 -maxdepth 1 -type d | while read -r folder; do
			system_name=$(basename "$folder")
			config_file="$emu_path/$system_name/config.json"
			sed -i 's/^{{*$/{/' "$config_file"
		done
	fi
	log_message "emufresh: showed all systems by fixing their config.json"

	# kill MainUI
	killall -9 MainUI

	# remove flag before exit
	flag_remove "emufresh"

	# exit with 0
	return 0
fi

# check folder PICO8 first
config_file="$emu_path/PICO8/config.json"
show_pico8=$(cat "$config_file" | grep -Fc '{{')
pico8_updated=false

DYN_OR_64="pico8_64"
[ "$PLATFORM" = "A30" ] && DYN_OR_64="pico8_dyn"

if [ -f "$emu_path/PICO8/bin/pico8.dat" ] &&
	[ -f "$emu_path/PICO8/bin/$DYN_OR_64" ]; then
	pico_files_present=1
elif [ -f "/mnt/SDCARD/BIOS/pico8.dat" ] &&
	[ -f "/mnt/SDCARD/BIOS/$DYN_OR_64" ]; then
	pico_files_present=1
elif [ -f "/media/sdcard1/BIOS/pico8.dat" ] &&
	[ -f "/media/sdcard1/BIOS/$DYN_OR_64" ]; then
	pico_files_present=1
else
	pico_files_present=0
fi

if [ "$pico_files_present" -eq 1 ]; then
	log_message "emufresh: pico8.dat and pico8_dyn or pico8_64 detected" -v
	if [ ! $show_pico8 = 0 ]; then
		pico8_updated=true
		rm -f "$roms_path/PICO8/PICO8_cache6.db"
		rm -f "$roms_path/PICO8/PICO8_cache7.db"
 		rm -f "$roms_path/PICO8/miyoogamelist.xml"
		if [ -d "$roms2_path" ]; then
			rm -f "$roms2_path/PICO8/PICO8_cache6.db"
			rm -f "$roms2_path/PICO8/PICO8_cache7.db"
			rm -f "$roms2_path/PICO8/miyoogamelist.xml"
		fi
 		sed -i 's/^{{*$/{/' "$config_file"
		echo "show system PICO8" && log_message "emufresh: revealing PICO8 system"
	fi
else
	if [ $show_pico8 = 0 ]; then
		log_message "emufresh: pico8.dat and pico8_dyn or pico8_64 not detected"
		pico8_updated=true
		sed -i 's/^{*$/{{/' "$config_file"
		echo "hide system PICO8" && log_message "emufresh: hiding PICO8 system"
	fi
fi

# read old md5 value for Roms folder
if [ -f "$md5_path/all.md5" ]; then
	all_md5=$(cat "$md5_path/all.md5" 2>/dev/null)
	log_message "emufresh: previous MD5 sum of all Roms folders is $all_md5" -v
fi
if [ -f "$md5_path/all2.md5" ]; then
	all2_md5=$(cat "$md5_path/all2.md5" 2>/dev/null)
	log_message "emufresh: previous MD5 sum of all SDCARD 2 Roms folders is $all2_md5" -v
fi

# compute new md5 value for files under Roms
# except known non-rom files
new_all_md5=$(find "$roms_path" -mindepth 2 -type f ! -path "*/.*" ! -path "*/Imgs/*" ! -path ".portmaster/*" ! -path ".32bit_chroot/*" ! -path "*/ports/*" ! -name "*.xml" ! -name "*.txt" ! -name ".gitkeep" ! -name "*cache6.db" | md5sum)
if [ -d "$roms2_path" ]; then
	new_all2_md5=$(find "$roms2_path" -mindepth 2 -type f ! -path "*/.*" ! -path "*/Imgs/*" ! -path ".portmaster/*" ! -path ".32bit_chroot/*" ! -path "*/ports/*" ! -name "*.xml" ! -name "*.txt" ! -name ".gitkeep" ! -name "*cache6.db" | md5sum)
fi

# if no update and no force option is used, exit with 0
if [ ! "$new_all_md5" = "$all_md5" ]; then
    echo [All] MD5 Changed : was $all_md5 but is now $new_all_md5 so refreshing
elif [ ! "$new_all2_md5" = "$all2_md5" ]; then
    echo [All] MD5 Changed : was $all2_md5 but is now $new_all2_md5 so refreshing
elif [ ! $pico8_updated ]; then
    echo [All] pico8 updated so refreshing
elif [ "$1" = "-force" ]; then
    echo [All] force arg passed so refreshing
else
	echo "no update" && log_message "emufresh: no update needed. Exiting!"

	# remove flag before exit
	flag_remove "emufresh"

	exit 0
fi

# otherwise update md5 file and continue
echo Writing $new_all_md5 to $md5_path/all.md5
echo "$new_all_md5" > "$md5_path/all.md5"
if [ -d "$roms2_path" ]; then
	echo Writing $new_all2_md5 to $md5_path/all2.md5
	echo "$new_all2_md5" > "$md5_path/all2.md5"
fi

# get all rom folders
rom_folders=$(find "$roms_path" -mindepth 1 -maxdepth 1 -type d)
rom2_folders=$(find "$roms2_path" -mindepth 1 -maxdepth 1 -type d)

# function to check list of rom folders
check_rom_folders() {
	# loop for all rom folders
	echo "$1" | while read -r folder; do
		# get system name
		system_name=$(basename "$folder")

		# get all file names except known non-rom files
		file_list=$(find "$folder" -mindepth 1 -type f ! -path "*/.*" ! -path "*/Imgs/*" ! -path ".portmaster/*" ! -path ".32bit_chroot/*" ! -path "*/ports/*" ! -name "*.xml" ! -name "*.txt" ! -name ".gitkeep" ! -name "*cache6.db" ! -name "*cache7.db" | sed '/^\s*$/d')

		# get old md5 value
		md5=$(cat "$md5_path/$system_name.md5" 2>/dev/null)

		# compute new md5 value
		new_md5=$(echo "$file_list" | md5sum)

		# check rom updates if md5 is different
		if [ ! "$new_md5" = "$md5" ]; then

			# store new md5 value
			echo [$system_name] Writing $new_md5 to $md5_path/$system_name.md5
			echo "$new_md5" >"$md5_path/$system_name.md5"

			log_message "emufresh: MD5 for $system_name has changed. Update required"

			# if config file exists
			config_file="$emu_path/$system_name/config.json"
			if [ -f "$config_file" ]; then
				echo [$system_name] using config file $config_file
				# get acceptable extensions
				types=$(jq -r '.extlist' "$config_file")

				if [ -z "$types" ]; then
					# count files in list					
					count=$(echo "$file_list" | sed '/^\s*$/d' | wc -l)
				else
					# count files with acceptable extension
					count=$(echo "$file_list" | sed '/^\s*$/d' | grep -icE "\.($types)$")
				fi

				# echo "$types"

			# if config file does not exist
			else
				echo [$system_name] $config_file does not exist
				# count files in list
				count=$(echo "$file_list" | wc -l)
			fi

			echo [$system_name] found $count files

			# hide / show system in MainUI
			if [ $count = 0 ]; then
				sed -i 's/^{*$/{{/' "$config_file"
				echo "[$system_name] hide system $system_name" && log_message "emufresh: Hiding $system_name"
			else
				rm -f "$roms_path/$system_name/${system_name}_cache6.db" "$roms_path/$system_name/${system_name}_cache7.db"
				[ "$system_name" = "ARCADE" ] || rm -f "$roms_path/$system_name/miyoogamelist.xml"
				[ "$system_name" = "PICO8" ] || sed -i 's/^{{*$/{/' "$config_file"
				echo "[$system_name] show system $system_name" && log_message "emufresh: Revealing $system_name"
				if [ -d "$roms2_path" ]; then
					rm -f "$roms2_path/$system_name/${system_name}_cache6.db" "$roms2_path/$system_name/${system_name}_cache7.db"
					[ "$system_name" = "ARCADE" ] || rm -f "$roms2_path/$system_name/miyoogamelist.xml"
					[ "$system_name" = "PICO8" ] || sed -i 's/^{{*$/{/' "$config_file"
					echo "[$system_name] show system $system_name" && log_message "emufresh: Revealing $system_name"
				fi
			fi
		fi
	done
}

# split the folder list into 4 sub-lists and check them parallelly in 4 processes
folders=$(echo "$rom_folders" | sed -n 'p;n;n;n')
check_rom_folders "$folders" &
folders=$(echo "$rom_folders" | sed -n 'n;p;n;n')
check_rom_folders "$folders" &
folders=$(echo "$rom_folders" | sed -n 'n;n;p;n')
check_rom_folders "$folders" &
folders=$(echo "$rom_folders" | sed -n 'n;n;n;p')
check_rom_folders "$folders"

# wait all process to finish
wait

# check for SDCARD 2 folders
if [ -d "$roms2_path" ]; then
	folders=$(echo "$rom2_folders" | sed -n 'p;n;n;n')
	check_rom_folders "$folders" &
	folders=$(echo "$rom2_folders" | sed -n 'n;p;n;n')
	check_rom_folders "$folders" &
	folders=$(echo "$rom2_folders" | sed -n 'n;n;p;n')
	check_rom_folders "$folders" &
	folders=$(echo "$rom2_folders" | sed -n 'n;n;n;p')
	check_rom_folders "$folders" 
fi

# wait all process to finish
wait
echo "all processes finished" && log_message "emufresh complete!"

# notify user to confirm restarting MainUI
if pgrep "MainUI" > /dev/null; then
	# pause MainUI
	killall -STOP MainUI

	# show dialog
	display -t "New emulators or roms detected, press confirm to restart the menu to see them immediately. Press cancel to see them next time you return to the menu." --confirm
	if confirm 10 0; then
		killall -9 MainUI
	else
		killall -CONT MainUI
	fi
fi

# remove flag before exit
flag_remove "emufresh"