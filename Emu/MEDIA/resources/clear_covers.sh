#!/bin/sh
# clear_covers.sh — remove all cover art from GVU's media folders
#
# Safe to run from DinguxCommander or SSH.
# Clears: /mnt/SDCARD/Roms/MEDIA/  (fully)
#         /mnt/SDCARD/Media/        (skips Media/Music/ and its subdirs)

count=0
tmplist="/tmp/gvu_clear_$$.txt"

clear_dir() {
    dir="$1"
    skip="$2"
    [ -d "$dir" ] || return
    # Write find results to a temp file so paths with spaces are handled correctly.
    # (for f in $(find ...) splits on whitespace, breaking "Season 1" etc.)
    find "$dir" \( -name "cover.jpg" -o -name "cover.png" \) > "$tmplist"
    while IFS= read -r f; do
        if [ -n "$skip" ]; then
            case "$f" in
                "$skip"/*) continue ;;
            esac
        fi
        rm -f "$f"
        echo "Removed: $f"
        count=$((count + 1))
    done < "$tmplist"
    rm -f "$tmplist"
}

clear_dir "/mnt/SDCARD/Roms/MEDIA" ""
clear_dir "/mnt/SDCARD/Media"      "/mnt/SDCARD/Media/Music"

echo "Done. Removed $count cover file(s)."
