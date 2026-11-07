#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SWAPFILE="/mnt/SDCARD/cachefile"

swap_setting="$(get_config_value '.menuOptions."System Settings".swapfileSize.selected' "Off")"
case "$swap_setting" in
    "128MB") min_swap_size_mb=128 ;;
    "256MB") min_swap_size_mb=256 ;;
    "512MB") min_swap_size_mb=512 ;;
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
    current_swap_size_bytes=$(du -k "${SWAPFILE}" | cut -f1)
    min_swap_size_bytes=$((min_swap_size_mb * 1024))
    if [ "$current_swap_size_bytes" -lt "$min_swap_size_bytes" ]; then
        swapoff "${SWAPFILE}"
        rm "${SWAPFILE}"
        log_message "Removed undersized swap file."
    fi
fi

if [ ! -f "${SWAPFILE}" ]; then
    if dd if=/dev/zero of="${SWAPFILE}" bs=1M count="$min_swap_size_mb"; then
        mkswap "${SWAPFILE}"
        sync
        log_message "Created new $min_swap_size_mb-MiB swap file."
    else
        log_message "Failed to create $min_swap_size_mb-MiB swap file — not enough space?"
        rm -f "${SWAPFILE}"
        exit 1
    fi
fi

case "$(swapon --help 2>&1)" in
    *"-p"*)
        swapon -p 40 "$SWAPFILE"
        ;;
    *)
        swapon "$SWAPFILE"
        ;;
esac || log_message "swapon command failed; proceeding without swap memory."

echo 10 > /proc/sys/vm/swappiness
