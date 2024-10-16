#!/bin/sh

emu_path="/mnt/SDCARD/Emu"
roms_path="/mnt/SDCARD/Roms"
md5_path="/mnt/SDCARD/spruce/flags/md5"

# ensure md5 folder exists
mkdir -p "$md5_path"

# read old md5 value for Roms folder
if [ -f "$md5_path/all.md5" ] ; then
	all_md5=$(cat "$md5_path/all.md5" 2>/dev/null)
fi

# compute new md5 value
new_all_md5=$(find "$roms_path" -mindepth 2 -type f ! -path "*/.*" ! -path "*/Imgs/*" ! -name *.xml ! -name *.txt ! -name ".gitkeep" ! -name "*cache6.db" | md5sum)
echo "$new_all_md5"

# if no update and no force option is used, exit with 0
if [ "$new_all_md5" = "$all_md5" ] && [ ! "$1" = "-force" ] ; then
	echo "no update"
	return 0

# otherwise update md5 file and continue
else
	echo "need update"
	echo "$new_all_md5" > "$md5_path/all.md5"
fi

# get all rom folders
rom_folders=$(find "$roms_path" -mindepth 1 -maxdepth 1 -type d -print)

# function to check list of rom folders
check_rom_folders() {
	# loop for all rom folders
	echo "$1" | while read -r folder; do
		# get system name
		system_name=$(basename "$folder")

		# get all file names except known non-rom files
		file_list=$(find "$folder" -mindepth 1 -type f ! -path "*/.*" ! -path "*/Imgs/*" ! -name *.xml ! -name *.txt ! -name ".gitkeep" ! -name "*cache6.db")
		
		# get old md5 value
		md5=$(cat "$md5_path/$system_name.md5" 2>/dev/null)

		# compute new md5 value
		new_md5=$(echo "$file_list" | md5sum)

		# check rom updates if md5 is different
		if [ ! "$new_md5" = "$md5" ] ; then

			# store new md5 value
			echo "$new_md5" > "$md5_path/$system_name.md5"

			# echo "$system_name need update"

			# if config file exists
			config_file="$emu_path/$system_name/config.json"
			if [ -f "$config_file" ]; then
				# get acceptable extensions
				types=$(cat "$config_file" | grep -m1 extlist | cut -d ":" -f 2 | sed "s/,//" | sed "s/ //" | sed "s/\	//" | sed 's/|\"/\"/g' | sed 's/\"//' | sed 's/\"//')
				
				# count files with acceptable extension
				count=$(echo "$file_list" | grep -icE "\.($types)$")

				# echo "$types"

			# if config file does not exist
			else
				# count files in list
				count=$(echo "$file_list" | wc -l)
			fi

			# hide / show system in MainUI
			if [ $count = 0 ]; then
				sed -i 's/^{*$/{{/' "$config_file"
				# echo "hide system"
			else
				sed -i 's/^{{*$/{/' "$config_file"
				# echo "show system"
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
echo "all processes finished"

# kill MainUI to refresh, it should restart by principle.sh very soon
killall -9 MainUI
echo "kill MainUI"

