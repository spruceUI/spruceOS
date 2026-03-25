#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
FIRSTBOOT_PACKAGE_PHASE_FLAG="firstboot_packages_extracting"

start_pyui_message_writer

flag_remove "first_boot_$PLATFORM"
log_message "Starting firstboot script on $PLATFORM"

SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"
FIRSTBOOT_PRE_EXTRACT_SCREENS="$SPRUCE_LOGO|Installing spruce $SPRUCE_VERSION|5"
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

run_firstboot_intro_phase() {
    run_firstboot_screen_table "$FIRSTBOOT_PRE_EXTRACT_SCREENS"

    SSH_SERVICE_NAME=$(get_ssh_service_name)
    if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
        log_message "Preparing SSH keys if necessary"
        dropbear_generate_keys &
    fi
}

run_firstboot_package_phase() {
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

    # Keep the branch's sequential firstboot contract, but use the current upstream
    # ScummVM packaging rules so firstboot only extracts the payloads needed by this device.
    SCUMMVM_DIR="/mnt/SDCARD/Emu/SCUMMVM"
    case "$PLATFORM" in
        "A30")       SCUMMVM_7Z="$SCUMMVM_DIR/scummvm_a30.7z" ;;
        "MiyooMini") SCUMMVM_7Z="$SCUMMVM_DIR/scummvm_mini.7z" ;;
        *)           SCUMMVM_7Z="$SCUMMVM_DIR/scummvm_64.7z" ;;
    esac

    MINI_SCUMMVM_ARCHIVES_FOUND=0
    if [ "$PLATFORM" = "MiyooMini" ] && [ -n "$(find "$SCUMMVM_DIR" -maxdepth 1 -name 'scummvm_mini_*.7z' | head -n 1)" ]; then
        MINI_SCUMMVM_ARCHIVES_FOUND=1
    fi

    if [ -f "$SCUMMVM_7Z" ] || [ "$MINI_SCUMMVM_ARCHIVES_FOUND" = "1" ]; then
        run_firstboot_screen_table "$SPRUCE_LOGO|Unpacking ScummVM|2"
    fi

    if [ -f "$SCUMMVM_7Z" ]; then
        SPRUCE_SUPPRESS_EXTRACT_PROGRESS_UI=1 extract_7z_with_progress "$SCUMMVM_7Z" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log "ScummVM"
    fi

    if [ "$PLATFORM" = "MiyooMini" ]; then
        for archive in "$SCUMMVM_DIR"/scummvm_mini_*.7z; do
            [ -f "$archive" ] || continue
            SPRUCE_SUPPRESS_EXTRACT_PROGRESS_UI=1 extract_7z_with_progress "$archive" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log "ScummVM"
        done
    fi

    rm -f "$SCUMMVM_DIR"/scummvm_*.7z
    chmod +x "$SCUMMVM_DIR"/scummvm.64 "$SCUMMVM_DIR"/scummvm.a30 "$SCUMMVM_DIR"/scummvm.mini "$SCUMMVM_DIR"/fixjoy 2>/dev/null

    flag_remove "$FIRSTBOOT_PACKAGE_PHASE_FLAG"
    "$SYSTEM_EMIT" process firstboot "PACKAGE_PHASE_END" "firstboot.sh/package-phase" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG" || true
}

run_firstboot_theme_phase() {
    # Themes are intentionally part of firstboot, but firstboot phase completion is not the
    # same thing as full boot completion. runtime.sh still owns the single closing UX once all
    # required foreground unpack work has finished cleanly.
    log_message "Firstboot: Running theme extraction phase before runtime-owned completion UX"
    "$SYSTEM_EMIT" process firstboot "THEME_PHASE_LAUNCH" "firstboot.sh/theme-phase" "run_mode=firstboot_theme_phase" || true

    if SPRUCE_FIRSTBOOT_UI="${SPRUCE_FIRSTBOOT_UI:-0}" /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh firstboot_theme_phase; then
        "$SYSTEM_EMIT" process firstboot "THEME_PHASE_RESULT" "firstboot.sh/theme-phase" "run_mode=firstboot_theme_phase status=success" || true
        return 0
    fi

    FIRSTBOOT_FINAL_STATE="FAILED"
    FIRSTBOOT_FINAL_REASON="firstboot-theme-phase-failed"
    "$SYSTEM_EMIT" process firstboot "THEME_PHASE_RESULT" "firstboot.sh/theme-phase" "run_mode=firstboot_theme_phase status=failed" || true
    log_message "Firstboot: Theme extraction phase failed; skipping firstboot wrap-up."
    return 1
}

run_firstboot_wrapup_phase() {
    if command -v A30_notify_about_FW_update_if_needed >/dev/null 2>&1; then
        A30_notify_about_FW_update_if_needed
    fi

    # create splore launcher if it doesn't already exist
    if [ ! -f "$SPLORE_CART" ]; then
        touch "$SPLORE_CART" && log_message "firstboot.sh: created $SPLORE_CART"
    else
        log_message "firstboot.sh: $SPLORE_CART already found."
    fi

    "$(get_python_path)" -O -m compileall /mnt/SDCARD/App/PyUI/main-ui/
}

run_firstboot_intro_phase
run_firstboot_package_phase
run_firstboot_theme_phase || exit $?
run_firstboot_wrapup_phase

log_message "Finished firstboot script"
"$SYSTEM_EMIT" process firstboot "COMPLETED" "firstboot.sh/shutdown" "platform=$PLATFORM" || true
