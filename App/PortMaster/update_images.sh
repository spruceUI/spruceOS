#Directory to search in
directory="/mnt/sdcard/Roms/PORTS"

mkdir -p "$directory/Imgs"

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

      echo Directory for [$file_name] is [$dir_name] which was extracted from [$gamedir_line]
      
      # If an image for the game doesn't already exist
      if [ ! -f "$directory/Imgs/$file_name.png" ]; then
          # Copy the cover if it exists, otherwise just copy the screenshot
          if [ -f "$directory/$dir_name/cover.png" ]; then
              cp "$directory/${dir_name}/cover.png" "$directory/Imgs/$file_name.png"         
          elif [ -f "$directory/$dir_name/screenshot.png" ]; then
              cp "$directory/${dir_name}/screenshot.png" "$directory/Imgs/$file_name.png"
          else
              echo No cover or screenshot found in $directory/$dir_name
          fi
      else
          echo $directory/Imgs/$file_name.png already exists
      fi
    
    fi
  fi
done
