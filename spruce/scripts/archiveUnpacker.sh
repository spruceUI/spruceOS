#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"
ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# This is a service to unpack archives that a preformatted to land in the right place.
# Since some files need to be available before the menu is displayed, we need to unpack them before the menu is displayed so that's one mode.
# The other mode is to unpack archives needed before the command_to_run, this is used for the preCmd folder.

# This can be called with a pre_cmd to run a check and unpack over the preCmd folder.

# Process command line arguments
SILENT_MODE=0
RUN_MODE="all"
if [ "$1" = "--silent" ]; then
    SILENT_MODE=1
    [ -n "$2" ] && RUN_MODE="$2"
elif [ -n "$1" ]; then
    RUN_MODE="$1"
fi

# Function to display text if not in silent mode
display_if_not_silent() {
    [ $SILENT_MODE -eq 0 ] && display "$@"
}

# Function to unpack archives from a specified directory
unpack_archives() {
    local dir="$1"
    local flag_name="$2"

    [ -n "$flag_name" ] && flag_add "$flag_name"

    for archive in "$dir"/*.7z; do
        if [ -f "$archive" ]; then
            archive_name=$(basename "$archive" .7z)
            display_if_not_silent --icon "$ICON" -t "$archive_name archive detected. Unpacking.........."

            if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
                if 7zr x -aoa "$archive" -o/; then
                    rm -f "$archive"
                    log_message "Unpacker: Unpacked and removed: $archive_name.7z"
                else
                    log_message "Unpacker: Failed to unpack: $archive_name.7z"
                fi
            else
                log_message "Unpacker: Skipped unpacking: $archive_name.7z (incorrect folder structure)"
            fi
        fi
    done

    [ -n "$flag_name" ] && flag_remove "$flag_name"
}

# Quick check for .7z files in relevant directories
if [ "$RUN_MODE" = "all" ] &&
    [ -z "$(find "$ARCHIVE_DIR/preCmd" -maxdepth 1 -name '*.7z' | head -n 1)" ] &&
    [ -z "$(find "$ARCHIVE_DIR/preMenu" -maxdepth 1 -name '*.7z' | head -n 1)" ] &&
    [ -z "$(find "$THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ] &&
    [ -z "$(find "$RA_THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ]; then
    log_message "Unpacker: No .7z files found to unpack. Exiting."
    exit 0
fi

log_message "Unpacker: Starting theme and archive unpacking process"

# Process archives based on run mode
case "$RUN_MODE" in
"all")
    unpack_archives "$THEME_DIR"
    unpack_archives "$ARCHIVE_DIR/preMenu" "pre_menu_unpacking"
    if flag_check "save_active"; then
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
    else
        SILENT_MODE=1
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking" &
    fi
    ;;
"pre_cmd")
    unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
    ;;
*)
    log_message "Unpacker: Invalid run mode specified"
    exit 1
    ;;
esac

log_message "Unpacker: Finished running"
