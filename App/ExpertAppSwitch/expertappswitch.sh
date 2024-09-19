#!/bin/sh

# Base directory containing the specific folders
BASE_DIR="/mnt/SDCARD/App/"

# List of specific folders to process
FOLDERS="LEDon BootLogo MiyooGamelist RetroExpert RecentSwitch sftpgo FileManagement SSH Syncthing"

# Iterate over each folder name
for folder in $FOLDERS; do
    # Construct the full path to the folder
    DIR="$BASE_DIR$folder"

    # Check if the directory exists
    if [ -d "$DIR" ]; then
        echo "Processing folder: $DIR"

        # Find and toggle config.json and config_hidden.json files
        find "$DIR" -type f \( -name "config.json" -o -name "config_hidden.json" \) | while read -r file; do
            # Determine the new file name
            case "$(basename "$file")" in
                config.json)
                    new_file="$(dirname "$file")/config_hidden.json"
                    ;;
                config_hidden.json)
                    new_file="$(dirname "$file")/config.json"
                    ;;
                *)
                    # Skip files that don't match the names we're interested in
                    continue
                    ;;
            esac
            
            # Rename the file
            mv "$file" "$new_file"
            
            echo "Renamed $file to $new_file"
        done
    else
        echo "Directory $DIR does not exist."
    fi
done

# Run the additional script at the end
/mnt/SDCARD/App/IconFresh/iconfreshLite.sh
