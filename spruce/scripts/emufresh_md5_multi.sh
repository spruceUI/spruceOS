#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

emu_path="/mnt/SDCARD/Emu"
roms_path="/mnt/SDCARD/Roms"
md5_path="/mnt/SDCARD/Emu/.emu_setup/md5"

log_message "emufresh: checking if emufresh required"

# ensure md5 folder exists
mkdir -p "$md5_path" && log_message "emufresh: created $md5_path"

# handle clear all option
if [ "$1" = "-clearall" ] ; then
	# remove all md5 files
	rm -r "$md5_path" && log_message "emufresh: removed $md5_path and its contents"
	
	# hide all systems
	find "$roms_path" -mindepth 1 -maxdepth 1 -type d | while read -r folder; do
		system_name=$(basename "$folder")
		config_file="$emu_path/$system_name/config.json"
		sed -i 's/^{*$/{{/' "$config_file"
	done
	log_message "emufresh: hid all systems by breaking their config.json"

	# kill MainUI
	killall -9 MainUI

	# exit with 0
	return 0
fi

# check folder PICO8 first
config_file="$emu_path/PICO8/config.json"
show_pico8=$(cat "$config_file" | grep -Fc '{{' )
need_restart_mainui=false
if [ -f "$emu_path/PICO8/bin/pico8.dat" ] &&
   [ -f "$emu_path/PICO8/bin/pico8_dyn" ] ; then
	log_message "emufresh: pico8.dat and pico8_dyn detected"
	if [ ! $show_pico8 = 0 ] ; then
		need_restart_mainui=true
		rm -f "$roms_path/PICO8/PICO8_cache6.db"
		sed -i 's/^{{*$/{/' "$config_file"
		echo "show system PICO8" && log_message "emufresh: revealing PICO8 system"
	fi
else
	if [ $show_pico8 = 0 ] ; then
		log_message "emufresh: pico8.dat and pico8_dyn not detected"
		need_restart_mainui=true
		sed -i 's/^{*$/{{/' "$config_file"
		echo "hide system PICO8" && log_message "emufresh: hiding PICO8 system"
	fi
fi

# read old md5 value for Roms folder
if [ -f "$md5_path/all.md5" ] ; then
	all_md5=$(cat "$md5_path/all.md5" 2>/dev/null)
	log_message "emufresh: previous MD5 sum of all Roms folders is $all_md5" -v
fi

# compute new md5 value for files under Roms 
# except known non-rom files and folders PICO8 
new_all_md5=$(find "$roms_path" -mindepth 2 -type f ! -path "$roms_path/PICO8/*" ! -path "*/.*" ! -path "*/Imgs/*" ! -name *.xml ! -name *.txt ! -name ".gitkeep" ! -name "*cache6.db" | md5sum)
echo "$new_all_md5" && log_message "emufresh: new MD5 sum of all Roms folders is $all_md5" -v

# if no update and no force option is used, exit with 0
if [ "$new_all_md5" = "$all_md5" ] && [ ! "$1" = "-force" ] ; then
	echo "no update" && log_message "emufresh: no update needed. Exiting!"
	# kill mainUI if pico8 files are updated
	if [ "$need_restart_mainui" = true ] ; then
		killall -9 MainUI
		echo "kill MainUI"
	fi
	return 0

# otherwise update md5 file and continue
else
	echo "need update" && log_message "emufresh: update needed!"
	echo "$new_all_md5" > "$md5_path/all.md5"
fi

# get all rom folders except folders PICO8
rom_folders=$(find "$roms_path" -mindepth 1 -maxdepth 1 -type d ! -path "$roms_path/PICO8")

# function to check list of rom folders
check_rom_folders() {
	# loop for all rom folders
	echo "$1" | while read -r folder; do
		# get system name
		system_name=$(basename "$folder")

		# get all file names except known non-rom files
		file_list=$(find "$folder" -mindepth 1 -type f ! -path "*/.*" ! -path "*/Imgs/*" ! -name *.xml ! -name *.txt ! -name ".gitkeep" ! -name "*cache6.db" | sed '/^\s*$/d')

		# get old md5 value
		md5=$(cat "$md5_path/$system_name.md5" 2>/dev/null)

		# compute new md5 value
		new_md5=$(echo "$file_list" | md5sum)

		# check rom updates if md5 is different
		if [ ! "$new_md5" = "$md5" ] ; then

			# store new md5 value
			echo "$new_md5" > "$md5_path/$system_name.md5"

			log_message "emufresh: MD5 for $system_name has changed. Update required"

			# if config file exists
			config_file="$emu_path/$system_name/config.json"
			if [ -f "$config_file" ]; then
				# get acceptable extensions
				types=$(cat "$config_file" | grep -m1 extlist | cut -d ":" -f 2 | sed "s/,//" | sed "s/ //" | sed "s/\	//" | sed 's/|\"/\"/g' | sed 's/\"//' | sed 's/\"//')

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
				# count files in list
				count=$(echo "$file_list" | wc -l)
			fi

			# hide / show system in MainUI
			if [ $count = 0 ]; then
				sed -i 's/^{*$/{{/' "$config_file"
				echo "hide system $system_name" && log_message "emufresh: Hiding $system_name"
			else
				rm -f "$roms_path/$system_name/${system_name}_cache6.db"
				sed -i 's/^{{*$/{/' "$config_file"
				echo "show system $system_name" && log_message "emufresh: Revealing $system_name"
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
echo "all processes finished" && log_message "emufresh complete!"

# kill MainUI to refresh, it should restart by principle.sh very soon
killall -9 MainUI
echo "kill MainUI"
return 0

