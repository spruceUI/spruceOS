#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SWAPFILE="/mnt/SDCARD/cachefile"
BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
[ "$PLATFORM" = "SmartPro" ] && BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png"

case "$PLATFORM" in
    "A30") MIN_MB=128 ;;
    * ) MIN_MB=512 ;;
esac

if [ -f "${SWAPFILE}" ]; then
    SWAPSIZE=$(du -k "${SWAPFILE}" | cut -f1)
    MINSIZE=$((MIN_MB * 1024))
    if [ "$SWAPSIZE" -lt "$MINSIZE" ]; then
        swapoff "${SWAPFILE}"
        rm "${SWAPFILE}"
        log_message "Removed undersized swap file."
    fi
fi

if [ ! -f "${SWAPFILE}" ]; then
    display -i "$BG_TREE" -t "Setting up swapfile..."
    if dd if=/dev/zero of="${SWAPFILE}" bs=1M count="$MIN_MB"; then
        mkswap "${SWAPFILE}"
        sync
        log_message "Created new $MIN_MB-MiB swap file."
    else
        log_message "Failed to create $MIN_MB-MiB swap file — not enough space?"
        rm -f "${SWAPFILE}"
        exit 1
    fi
fi

swapon -p 40 "${SWAPFILE}" || swapon "$SWAPFILE" || log_message "swapon command failed; proceeding without swap memory."
echo 10 > /proc/sys/vm/swappiness
display_kill
