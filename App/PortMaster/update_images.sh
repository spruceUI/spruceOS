#Directory to search in
directory="/mnt/sdcard/Roms/PORTS"

mkdir -p "$directory/Imgs"

# Define the list of image base names
image_names=("cover" "screenshot" "splash")

# Ensure pillow is installed 
if [ ! -d "/sdcard/Roms/.portmaster/site-packages/PIL/" ] ; then
    /mnt/sdcard/Roms/.portmaster/bin/python3 -m pip install --no-index --find-links=/mnt/sdcard/App/PortMaster/pillow_offline Pillow
fi


# Loop through each file in the directory
for file in "$directory"/*; do
  # Check if it is a regular file
  if [ -f "$file" ]; then
    # Get the line starting with "GAMEDIR=" and assign it to a variable
    gamedir_line=$(grep "^GAMEDIR=" "$file")

    # Check if a line was found
    if [ -n "$gamedir_line" ]; then
      # Extract the file_name without extension
      file_name=$(basename "$file" .${file##*.})

      # If gamedir_name ends with a slash, remove the slash
      gamedir_line="${gamedir_line%/}"
      
      # Extract everything after the last '/' in the GAMEDIR line and assign it to dir_name
      dir_name="${gamedir_line##*/}"

      # If dir_name ends with a quote, remove the quote
      dir_name="${dir_name%\"}"
      
      # If an image for the game doesn't already exist
      if [ ! -f "$directory/Imgs/$file_name.png" ]; then				  

		# Loop through the list to convert jpg to png
		for name in "${image_names[@]}"; do
			jpg_path="$directory/$dir_name/${name}.jpg"
			if [ -f "$jpg_path" ]; then
				echo "Converting $jpg_path to png"
				/mnt/sdcard/Roms/.portmaster/bin/python3 /mnt/sdcard/App/PortMaster/jpg_to_png.py "$jpg_path"
				break
			fi
		done

		# Loop through the list again to copy the first existing png to the target location
		for name in "${image_names[@]}"; do
			png_path="$directory/$dir_name/${name}.png"
			if [ -f "$png_path" ]; then
				cp "$png_path" "$directory/Imgs/$file_name.png"
				break
			fi
		done
      fi
    
    fi
  fi
done
