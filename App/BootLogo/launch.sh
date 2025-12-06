#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR=/mnt/SDCARD/App/BootLogo
IMG_DIR="$APP_DIR/Imgs"
INSTALL="/mnt/SDCARD/App/BootLogo/install_logo.sh"

construct_config() {
    cd "$IMG_DIR" || return 1
    echo "{" > "$APP_DIR/bootlogo.json"

    for logo in /mnt/SDCARD/App/BootLogo/Imgs/* ; do
        file_ext=""
        case "$logo" in
            *"Yes, flash"*) continue ;; # ignore confirmation images
            *".bmp") file_ext=".bmp" ;;
            *".png") file_ext=".png" ;;
            *)       continue        ;; # ignore non-bmp/png files
        esac
        logo_name="$(basename "$logo" "$file_ext")" 
        cp -f "$logo" "$IMG_DIR/Yes, flash ${logo_name}${file_ext}"
        echo "\"$logo_name/Yes, flash $logo_name\": \"cp -f '$logo' '$APP_DIR/bootlogo${file_ext}'\"," >> "$APP_DIR/bootlogo.json"
    done

    sed -i '$ s/,$//' "$APP_DIR/bootlogo.json"      # strip away final trailing comma
    echo "}" >> "$APP_DIR/bootlogo.json"
    return 0
}

##### MAIN EXECUTION #####

mv -f /mnt/SDCARD/App/BootLogo/bootlogo.png /mnt/SDCARD/App/BootLogo/bootlogo.png.bak 2>/dev/null

start_pyui_message_writer
log_and_display_message "Preparing boot logo selection menu. Please wait.........."


if ! construct_config; then
    log_and_display_message "Could not find App/BootLogo/Imgs folder. Exiting."
    sleep 3
    exit 1
fi

RESULT_FILE="/mnt/SDCARD/App/PyUI/selection.txt"
rm -f "$RESULT_FILE"

display_option_list "$APP_DIR/bootlogo.json"
while true; do
    if [ -f "$RESULT_FILE" ]; then
        content=$(cat "$RESULT_FILE" 2>/dev/null)
        if [ "$content" = "EXIT" ]; then
            log_and_display_message "No bootlogo selected. Exiting."
            sleep 2
            break
        else
            log_message "$content"
            # Execute the content of the file as a command
            eval "$content"
            rm -f "$RESULT_FILE"
            "$INSTALL"
            break
        fi
    fi
done

mv -f /mnt/SDCARD/App/BootLogo/bootlogo.png.bak /mnt/SDCARD/App/BootLogo/bootlogo.png 2>/dev/null
