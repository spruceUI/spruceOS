#Directory to search in
directory="/mnt/sdcard/Roms/PORTS"

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

      # Extract everything after the last '/' in the GAMEDIR line and assign it to dir_name
      dir_name="${gamedir_line##*/}"

      # If dir_name ends with a quote, remove the quote
      dir_name="${dir_name%\"}"

      # If an image for the game doesn't already exist
      if [ ! -f "$directory/Imgs/$file_name.png" ]; then
          # Copy the cover if it exists, otherwise just copy the screenshot
          if [ -f "$directory/$dir_name/cover.png" ]; then
              cp "$directory/${dir_name}/cover.png" "$directory/Imgs/$file_name.png"         
          elif [ -f "$directory/$dir_name/screenshot.png" ]; then
              cp "$directory/${dir_name}/screenshot.png" "$directory/Imgs/$file_name.png"
          fi
      fi
    
    fi
  fi
done
