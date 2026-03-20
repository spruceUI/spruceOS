#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
SYSTEM_EMIT="${SYSTEM_EMIT:-/mnt/SDCARD/spruce/scripts/system-emit}"
FIRSTBOOT_PACKAGE_PHASE_FLAG="firstboot_packages_extracting"

start_pyui_message_writer

flag_remove "first_boot_$PLATFORM"
log_message "Starting firstboot script on $PLATFORM"
"$SYSTEM_EMIT" process firstboot "STARTED" "firstboot.sh/startup" "platform=$PLATFORM" || true

WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"
FIRSTBOOT_PRE_EXTRACT_SCREENS="$SPRUCE_LOGO|Installing spruce $SPRUCE_VERSION|5"
FIRSTBOOT_POST_EXTRACT_SCREENS="$WIKI_ICON|Check out the spruce wiki on our GitHub page for tips and FAQs!|5"
FIRSTBOOT_FINAL_STATE="COMPLETE"
FIRSTBOOT_FINAL_REASON="normal-exit"
FIRSTBOOT_FINALIZED=0

firstboot_trace_finalize() {
    [ "$FIRSTBOOT_FINALIZED" = "1" ] && return 0
    "$SYSTEM_EMIT" process-finalize firstboot "firstboot.sh" "$FIRSTBOOT_FINAL_STATE" "reason=$FIRSTBOOT_FINAL_REASON platform=$PLATFORM" || true
    FIRSTBOOT_FINALIZED=1
}

cleanup_firstboot() {
    flag_remove "$FIRSTBOOT_PACKAGE_PHASE_FLAG"
    firstboot_trace_finalize
}
trap cleanup_firstboot EXIT

"$SYSTEM_EMIT" process-init firstboot "firstboot.sh" "platform=$PLATFORM" || true

show_firstboot_screen() {
    img="$1"
    text="$2"
    duration="${3:-5}"
    if [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ]; then
        case "$text" in
            "Check out the spruce wiki on our GitHub page for tips and FAQs!"*) ;;
            *) text="Sprucing up your device...\n${text}" ;;
        esac
    fi

    display_image_and_text "$img" 35 25 "$text" 75
    sleep "$duration"
}

run_firstboot_screen_table() {
    table_rows="$1"
    [ -n "$table_rows" ] || return 0

    printf '%s\n' "$table_rows" | while IFS='|' read -r img text duration; do
        [ -n "$img" ] || continue
        show_firstboot_screen "$img" "$text" "${duration:-5}"
    done
}

run_firstboot_screen_table "$FIRSTBOOT_PRE_EXTRACT_SCREENS"

SSH_SERVICE_NAME=$(get_ssh_service_name)
if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
    log_message "Preparing SSH keys if necessary"
    dropbear_generate_keys &
fi

flag_add "$FIRSTBOOT_PACKAGE_PHASE_FLAG" --tmp
"$SYSTEM_EMIT" process firstboot "PACKAGE_PHASE_BEGIN" "firstboot.sh/package-phase" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG" || true

if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ]; then
    mkdir -p /mnt/SDCARD/Persistent/
    if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
        extract_7z_with_progress /mnt/SDCARD/App/PortMaster/portmaster.7z /mnt/SDCARD/Persistent/ /mnt/SDCARD/Saves/spruce/portmaster_extract.log "PortMaster"
    else
        run_firstboot_screen_table "$SPRUCE_LOGO|Unpacking PortMaster\nAlready installed|2"
    fi

    rm -f /mnt/SDCARD/App/PortMaster/portmaster.7z
else
    display_image_and_text "$SPRUCE_LOGO" 35 25 "Sprucing up your device" 75
fi

# Extract ScummVM standalone binaries (64-bit only)
if [ "$PLATFORM_ARCHITECTURE" != "armhf" ]; then
    SCUMMVM_DIR="/mnt/SDCARD/Emu/SCUMMVM"
    for SCUMMVM_7Z in "$SCUMMVM_DIR"/scummvm_*.7z; do
        [ -f "$SCUMMVM_7Z" ] || continue
        extract_7z_with_progress "$SCUMMVM_7Z" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log "Installing ScummVM"
        rm -f "$SCUMMVM_7Z"
    done
fi

flag_remove "$FIRSTBOOT_PACKAGE_PHASE_FLAG"
"$SYSTEM_EMIT" process firstboot "PACKAGE_PHASE_END" "firstboot.sh/package-phase" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG" || true

log_message "Firstboot: Running themes-only archive extraction before final transition screens"
"$SYSTEM_EMIT" process archiveUnpacker "FIRSTBOOT_THEMES_ONLY_LAUNCH" "firstboot.sh/themes-only" "run_mode=themes_only" || true
SPRUCE_FIRSTBOOT_UI="${SPRUCE_FIRSTBOOT_UI:-0}" /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh themes_only
"$SYSTEM_EMIT" process archiveUnpacker "FIRSTBOOT_THEMES_ONLY_RESULT" "firstboot.sh/themes-only" "run_mode=themes_only completed" || true

run_firstboot_screen_table "$FIRSTBOOT_POST_EXTRACT_SCREENS"

perform_fw_check

# create splore launcher if it doesn't already exist
if [ ! -f "$SPLORE_CART" ]; then
	touch "$SPLORE_CART" && log_message "firstboot.sh: created $SPLORE_CART"
else
	log_message "firstboot.sh: $SPLORE_CART already found."
fi

"$(get_python_path)" -O -m compileall /mnt/SDCARD/App/PyUI/main-ui/
log_message "Finished firstboot script"
"$SYSTEM_EMIT" process firstboot "COMPLETED" "firstboot.sh/shutdown" "platform=$PLATFORM" || true
