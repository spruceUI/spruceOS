#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ICON_PATH="/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"
ROMS_DIR="/mnt/SDCARD/Roms"
SYSTEM="$(echo "$1" | cut -d'/' -f5)"

case "$SYSTEM" in
    AMIGA) DISC_EXTS="cue|ccd|chd|iso|adf|adz|dms|fdi|ipf|hdf|hdz" ;;
    ATARIST) DISC_EXTS="st|msa|stx|dim|ipf" ;;
    COLECO|CPC|MSX) DISC_EXTS="dsk" ;;
    COMMODORE|VIC20) DISC_EXTS="d64|d6z|d71|d7z|d80|d81|d82|d8z|g64|g6z|g41|g4z|x64|x6z|nib|nbz|d2m|d4m" ;;
    DOS) DISC_EXTS="cue|chd|iso|img|ima|vhd" ;;
    PCFX) DISC_EXTS="cue|ccd|toc|chd" ;;
    X68000) DISC_EXTS="dim|img|d88|88d|hdm|dup|2hd|xdf|hdf" ;;
    *) DISC_EXTS="cue|gdi|chd|pbp|iso|cdi|ccd|mds" ;;
esac

generate_cues() {
    cd "$ROMS_DIR"
    find $SYSTEM -maxdepth 3 -type f -name "*.bin" | while read -r target; do
        dirname="$(dirname "$target")"
        basename="$(basename "$target")"
        cuename="${basename%.*}"
        cuepath="$dirname/$cuename.cue"

        if echo "$cuename" | grep -q ' (Track [0-9][0-9]*)$' || [ -f "$cuepath" ]; then
            continue
        fi 

        echo "FILE \"$basename\" BINARY
  TRACK 01 MODE1/2352
    INDEX 01 00:00:00" > "$cuepath"
    done

    find $SYSTEM -maxdepth 1 -type f -iname "*_cache[6-7].db" -exec rm -f {} +
}

start_pyui_message_writer
display_image_and_text "$ICON_PATH" "Generating M3Us... this shouldn't take longer than a few seconds."

case "$SYSTEM" in
    AMIGA|ATOMISWAVE|DC|NAOMI|NEOCD|PCECD|PS|SATURN|SEGACD) generate_cues ;;
esac

FULLPATH="$ROMS_DIR/$SYSTEM"

if [ -d "$FULLPATH" ]; then
    cd "$FULLPATH"
    # Redump/No-Intro (revisionless)
    find . -maxdepth 1 -type f -iname "*([Dd][Ii][Ss][KkCc] 1).*" | grep -iE "\\.($DISC_EXTS)$" | while read -r line; do
        FILENAME="$(echo "${line%.*}" | sed 's@./@@g' | sed 's@ ([Dd][Ii][Ss][KkCc] 1)@@g')"
        DIRNAME=".${FILENAME%"${FILENAME##*[![:space:]]}"}" # remove spaces at the end
        SEARCH_NAME="$(echo "${line%.*}" | sed 's@./@@g' | sed 's@([Dd][Ii][Ss][KkCc] 1)@([Dd][Ii][Ss][KkCc] ?)@g')"

        sync
        mkdir -p "$DIRNAME"

        find . -maxdepth 1 ! -iname '*.m3u' -type f -iname "$SEARCH_NAME*" -exec mv -n -- '{}' "$DIRNAME" \; # move discs + tracks to directory
        find "$DIRNAME" -type f -iname "$SEARCH_NAME*.*" | grep -iE "\\.($DISC_EXTS)$" | sort > "$FILENAME.m3u"  # create playlist of discs
    done

    # Redump/No-Intro (with revisions)
    find . -maxdepth 1 -type f -iname "*([Dd][Ii][Ss][KkCc] 1) *.*" | grep -iE "\\.($DISC_EXTS)$" | while read -r line; do
        FILENAME="$(echo "${line%.*}" | sed 's@./@@g' | sed 's@ ([Dd][Ii][Ss][KkCc] 1)@@g')"
        DIRNAME=".${FILENAME%"${FILENAME##*[![:space:]]}"}" # remove spaces at the end
        SEARCH_NAME="$(echo "${line%.*}" | sed 's@./@@g' | sed 's@([Dd][Ii][Ss][KkCc] 1)@([Dd][Ii][Ss][KkCc] ?)@g')"

        sync
        mkdir -p "$DIRNAME"

        find . -maxdepth 1 ! -iname '*.m3u' -type f -iname "$SEARCH_NAME*" -exec mv -n -- '{}' "$DIRNAME" \; # move discs + tracks to directory
        find "$DIRNAME" -type f -iname "$SEARCH_NAME*.*" | grep -iE "\\.($DISC_EXTS)$" | sort > "$FILENAME.m3u" # create playlist of discs
    done

    # TOSEC
    find . -maxdepth 1 -type f -iname "*([Dd][Ii][Ss][KkCc] 1 of ?).*" | grep -iE "\\.($DISC_EXTS)$" | while read -r line; do
        FILENAME="$(echo "${line%.*}" | sed 's@./@@g' | sed 's@([Dd][Ii][Ss][KkCc] 1 of .*)@@g')"
        DIRNAME=".${FILENAME%"${FILENAME##*[![:space:]]}"}" # remove spaces at the end
        SEARCH_NAME="$(echo "${line%.*}" | sed 's@./@@g' | sed 's@([Dd][Ii][Ss][KkCc] 1 of@([Dd][Ii][Ss][KkCc] ? of@g')"

        sync
        mkdir -p "$DIRNAME"

        find . -maxdepth 1 ! -iname '*.m3u' -type f -iname "$SEARCH_NAME*" -exec mv -n -- '{}' "$DIRNAME" \; # move discs + tracks to directory
        find "$DIRNAME" -type f -iname "$SEARCH_NAME*.*" | grep -iE "\\.($DISC_EXTS)$" | sort > "$FILENAME.m3u" # create playlist of discs
    done
else
    echo "Directory $FULLPATH does not exist."
fi

cd "$ROMS_DIR"
find $SYSTEM -maxdepth 1 -type f -iname "*_cache[6-7].db" -exec rm -f {} +
sync

sleep 2
stop_pyui_message_writer
auto_regen_tmp_update