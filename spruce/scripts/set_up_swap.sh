#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SWAPFILE="/mnt/SDCARD/cachefile"

swap_setting="$(get_config_value '.menuOptions."System Settings".swapfileSize.selected' "Off")"
case "$swap_setting" in
    "128MB") MIN_MB=128 ;;
    "256MB") MIN_MB=256 ;;
    "512MB") MIN_MB=512 ;;
    * ) log_message "No swapfile requested by user settings."
        if [ -f "${SWAPFILE}" ]; then
            swapoff "${SWAPFILE}"
            rm "${SWAPFILE}"
            log_message "Removed extraneous swap file."
        fi
        exit 0
        ;;
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
