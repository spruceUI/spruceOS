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
FIRSTBOOT_ARCHIVE_TOTAL=0
FIRSTBOOT_ARCHIVE_COMPLETED=0
FIRSTBOOT_PROGRESS_STATE_FILE="/tmp/firstboot_extract_progress_state"

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

write_firstboot_progress_state() {
    tmp_state="${FIRSTBOOT_PROGRESS_STATE_FILE}.$$"

    {
        printf 'total=%s\n' "$FIRSTBOOT_ARCHIVE_TOTAL"
        printf 'completed=%s\n' "$FIRSTBOOT_ARCHIVE_COMPLETED"
    } > "$tmp_state"
    mv -f "$tmp_state" "$FIRSTBOOT_PROGRESS_STATE_FILE"
}

count_archives_matching() {
    dir="$1"
    pattern="$2"
    count=0

    for archive in "$dir"/$pattern; do
        [ -f "$archive" ] || continue
        count=$((count + 1))
    done

    printf '%s\n' "$count"
}

log_firstboot_archive_status() {
    event="$1"
    label="$2"
    status="$3"
    extra_context="$4"
    percent="$(calculate_progress_percent "$FIRSTBOOT_ARCHIVE_COMPLETED" "$FIRSTBOOT_ARCHIVE_TOTAL")"

    log_message "Firstboot: archive_progress event=$event label=$label status=$status progress=${percent}% completed=$FIRSTBOOT_ARCHIVE_COMPLETED total=$FIRSTBOOT_ARCHIVE_TOTAL ${extra_context}"
    "$SYSTEM_EMIT" process firstboot "$event" "firstboot.sh/archive-progress" "label=$label status=$status completed=$FIRSTBOOT_ARCHIVE_COMPLETED total=$FIRSTBOOT_ARCHIVE_TOTAL percent=$percent ${extra_context}" || true
}

show_firstboot_archive_progress() {
    [ "$FIRSTBOOT_ARCHIVE_TOTAL" -gt 0 ] || return 0
    write_firstboot_progress_state
    display_firstboot_extract_progress "$FIRSTBOOT_ARCHIVE_COMPLETED" "$FIRSTBOOT_ARCHIVE_TOTAL" "$SPRUCE_LOGO"
}

run_firstboot_archive_extract() {
    archive_path="$1"
    dest_dir="$2"
    log_location="$3"
    label="$4"

    [ -f "$archive_path" ] || return 0

    archive_name="$(basename "$archive_path")"
    log_firstboot_archive_status "ARCHIVE_BEGIN" "$label" "start" "archive=$archive_name"
    SPRUCE_SUPPRESS_EXTRACT_PROGRESS_UI=1 extract_7z_with_progress "$archive_path" "$dest_dir" "$log_location" "$label"
    rc=$?
    FIRSTBOOT_ARCHIVE_COMPLETED=$((FIRSTBOOT_ARCHIVE_COMPLETED + 1))
    show_firstboot_archive_progress

    if [ "$rc" -eq 0 ]; then
        log_firstboot_archive_status "ARCHIVE_RESULT" "$label" "success" "archive=$archive_name rc=$rc"
    else
        log_firstboot_archive_status "ARCHIVE_RESULT" "$label" "failed" "archive=$archive_name rc=$rc"
    fi

    return "$rc"
}

run_firstboot_package_phase() {
    flag_add "$FIRSTBOOT_PACKAGE_PHASE_FLAG" --tmp
    "$SYSTEM_EMIT" process firstboot "PACKAGE_PHASE_BEGIN" "firstboot.sh/package-phase" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG" || true
    SCUMMVM_DIR="/mnt/SDCARD/Emu/SCUMMVM"
    case "$PLATFORM" in
        "A30")       SCUMMVM_7Z="$SCUMMVM_DIR/scummvm_a30.7z" ;;
        "MiyooMini") SCUMMVM_7Z="$SCUMMVM_DIR/scummvm_mini.7z" ;;
        *)           SCUMMVM_7Z="$SCUMMVM_DIR/scummvm_64.7z" ;;
    esac

    ADVMAME_DIR="/mnt/SDCARD/Emu/ARCADE"
    ADVMAME_7Z=""
    case "$PLATFORM" in
        "Brick" | "SmartPro" | "SmartProS" | "Flip")
            ADVMAME_7Z="$ADVMAME_DIR/advmame.7z"
            ;;
    esac

    PORTMASTER_ARCHIVE_COUNT=0
    if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ] && [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] && [ -f /mnt/SDCARD/App/PortMaster/portmaster.7z ]; then
        PORTMASTER_ARCHIVE_COUNT=1
    fi

    SCUMMVM_ARCHIVE_COUNT=0
    if [ -f "$SCUMMVM_7Z" ]; then
        SCUMMVM_ARCHIVE_COUNT=$((SCUMMVM_ARCHIVE_COUNT + 1))
    fi
    if [ "$PLATFORM" = "MiyooMini" ]; then
        SCUMMVM_ARCHIVE_COUNT=$((SCUMMVM_ARCHIVE_COUNT + $(count_archives_matching "$SCUMMVM_DIR" 'scummvm_mini_*.7z')))
    fi

    ADVMAME_ARCHIVE_COUNT=0
    if [ -n "$ADVMAME_7Z" ] && [ -f "$ADVMAME_7Z" ]; then
        ADVMAME_ARCHIVE_COUNT=1
    fi

    FIRSTBOOT_THEME_ARCHIVE_TOTAL="$(count_archives_matching "/mnt/SDCARD/Themes" '*.7z')"
    FIRSTBOOT_PREMENU_ARCHIVE_TOTAL="$(count_archives_matching "/mnt/SDCARD/spruce/archives/preMenu" '*.7z')"
    FIRSTBOOT_PRECMD_ARCHIVE_TOTAL="$(count_archives_matching "/mnt/SDCARD/spruce/archives/preCmd" '*.7z')"
    FIRSTBOOT_ARCHIVE_TOTAL=$((PORTMASTER_ARCHIVE_COUNT + SCUMMVM_ARCHIVE_COUNT + ADVMAME_ARCHIVE_COUNT + FIRSTBOOT_THEME_ARCHIVE_TOTAL + FIRSTBOOT_PREMENU_ARCHIVE_TOTAL + FIRSTBOOT_PRECMD_ARCHIVE_TOTAL))

    log_firstboot_archive_status "ARCHIVE_PLAN" "all" "plan" "package_total=$((PORTMASTER_ARCHIVE_COUNT + SCUMMVM_ARCHIVE_COUNT + ADVMAME_ARCHIVE_COUNT)) theme_total=$FIRSTBOOT_THEME_ARCHIVE_TOTAL pre_menu_total=$FIRSTBOOT_PREMENU_ARCHIVE_TOTAL pre_cmd_total=$FIRSTBOOT_PRECMD_ARCHIVE_TOTAL"
    show_firstboot_archive_progress

    if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ]; then
        mkdir -p /mnt/SDCARD/Persistent/
        if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
            run_firstboot_archive_extract /mnt/SDCARD/App/PortMaster/portmaster.7z /mnt/SDCARD/Persistent/ /mnt/SDCARD/Saves/spruce/portmaster_extract.log "PortMaster"
        else
            log_message "Firstboot: PortMaster already installed, skipping archive extraction"
            "$SYSTEM_EMIT" process firstboot "ARCHIVE_SKIP" "firstboot.sh/archive-progress" "label=PortMaster status=already-installed completed=$FIRSTBOOT_ARCHIVE_COMPLETED total=$FIRSTBOOT_ARCHIVE_TOTAL" || true
        fi

        rm -f /mnt/SDCARD/App/PortMaster/portmaster.7z
    fi

    if [ -f "$SCUMMVM_7Z" ]; then
        run_firstboot_archive_extract "$SCUMMVM_7Z" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log "ScummVM"
    fi

    if [ "$PLATFORM" = "MiyooMini" ]; then
        for archive in "$SCUMMVM_DIR"/scummvm_mini_*.7z; do
            [ -f "$archive" ] || continue
            run_firstboot_archive_extract "$archive" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log "ScummVM"
        done
    fi

    rm -f "$SCUMMVM_7Z"
    if [ "$PLATFORM" = "MiyooMini" ]; then
        rm -f "$SCUMMVM_DIR"/scummvm_mini_*.7z
    fi
    chmod +x "$SCUMMVM_DIR"/scummvm.64 "$SCUMMVM_DIR"/scummvm.a30 "$SCUMMVM_DIR"/scummvm.mini "$SCUMMVM_DIR"/fixjoy 2>/dev/null

    if [ -n "$ADVMAME_7Z" ] && [ -f "$ADVMAME_7Z" ]; then
        run_firstboot_archive_extract "$ADVMAME_7Z" "$ADVMAME_DIR" /mnt/SDCARD/Saves/spruce/advmame_extract.log "AdvanceMAME"
    fi

    rm -f "$ADVMAME_DIR"/advmame.7z
    chmod +x "$ADVMAME_DIR"/advmame 2>/dev/null

    log_firstboot_archive_status "PACKAGE_PHASE_STATUS" "package-phase" "complete" "completed=$FIRSTBOOT_ARCHIVE_COMPLETED"
    flag_remove "$FIRSTBOOT_PACKAGE_PHASE_FLAG"
    "$SYSTEM_EMIT" process firstboot "PACKAGE_PHASE_END" "firstboot.sh/package-phase" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG" || true
}

run_firstboot_theme_phase() {
    # Themes are intentionally part of firstboot, but firstboot phase completion is not the
    # same thing as full boot completion. runtime.sh still owns the single closing UX once all
    # required foreground unpack work has finished cleanly, including the degraded-warning path.
    log_message "Firstboot: Running theme extraction phase before runtime-owned completion UX"
    "$SYSTEM_EMIT" process firstboot "THEME_PHASE_LAUNCH" "firstboot.sh/theme-phase" "run_mode=firstboot_theme_phase completed=$FIRSTBOOT_ARCHIVE_COMPLETED total=$FIRSTBOOT_ARCHIVE_TOTAL" || true

    if SPRUCE_FIRSTBOOT_UI="${SPRUCE_FIRSTBOOT_UI:-0}" \
        SPRUCE_FIRSTBOOT_ARCHIVE_TOTAL="$FIRSTBOOT_ARCHIVE_TOTAL" \
        SPRUCE_FIRSTBOOT_ARCHIVE_COMPLETED="$FIRSTBOOT_ARCHIVE_COMPLETED" \
        /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh firstboot_theme_phase; then
        "$SYSTEM_EMIT" process firstboot "THEME_PHASE_RESULT" "firstboot.sh/theme-phase" "run_mode=firstboot_theme_phase status=success" || true
        return 0
    fi

    FIRSTBOOT_FINAL_STATE="WARNING"
    FIRSTBOOT_FINAL_REASON="theme-phase-degraded"
    "$SYSTEM_EMIT" process firstboot "THEME_PHASE_RESULT" "firstboot.sh/theme-phase" "run_mode=firstboot_theme_phase status=warning" || true
    log_message "Firstboot: Theme extraction phase completed with warnings; continuing to wrap-up."
    return 2
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
run_firstboot_theme_phase
theme_phase_rc=$?
case "$theme_phase_rc" in
    0) ;;
    2) ;;
    *) exit "$theme_phase_rc" ;;
esac
run_firstboot_wrapup_phase

log_message "Finished firstboot script"
"$SYSTEM_EMIT" process firstboot "COMPLETED" "firstboot.sh/shutdown" "platform=$PLATFORM" || true
if [ "$theme_phase_rc" -eq 2 ]; then
    exit 2
fi
