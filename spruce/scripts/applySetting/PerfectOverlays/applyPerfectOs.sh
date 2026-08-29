#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/retroarch_utils.sh

apply_offset_filter() {
    log_message "Applying GBAOffset.filt for MiyooMini"
    update_ra_config_file_with_new_setting \
        /mnt/SDCARD/RetroArch/.retroarch/config/gpSP/gpSP.cfg \
        "video_filter = \":/.retroarch/filters/video/GBAOffset.filt\""
    update_ra_config_file_with_new_setting \
        /mnt/SDCARD/RetroArch/.retroarch/config/mGBA/mGBA.cfg \
        "video_filter = \":/.retroarch/filters/video/GBA/GBAOffset.filt\""
}

remove_offset_filter() {
    log_message "Removing GBAOffset.filt"
    update_ra_config_file_with_new_setting \
        /mnt/SDCARD/RetroArch/.retroarch/config/gpSP/gpSP.cfg \
        "video_filter = \"\""
    update_ra_config_file_with_new_setting \
        /mnt/SDCARD/RetroArch/.retroarch/config/mGBA/mGBA.cfg \
        "video_filter = \"\""
}

if [ "$1" = "True" ]; then
    if ! flag_check "perfectOverlays"; then
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GB.sh apply
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBC.sh apply
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBA.sh apply
        log_message "Turning on Perfect Overlays"
        flag_add "perfectOverlays"
    fi

    case "$PLATFORM" in
        "MiyooMini"*)
            if ! grep -q "GBAOffset.filt" /mnt/SDCARD/RetroArch/.retroarch/config/gpSP/gpSP.cfg; then
                apply_offset_filter
            fi
            ;;
        *)
            if grep -q "GBAOffset.filt" /mnt/SDCARD/RetroArch/.retroarch/config/gpSP/gpSP.cfg; then
                remove_offset_filter
            fi
            ;;
    esac


elif [ "$1" = "False" ]; then
    if flag_check "perfectOverlays"; then
        remove_offset_filter
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GB.sh remove
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBC.sh remove
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBA.sh remove
        log_message "Turning off Perfect Overlays"
        flag_remove "perfectOverlays"
    fi
fi
