#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"
ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"
STATE_FILE="/mnt/SDCARD/Saves/spruce/unpacker_state"
FIRSTBOOT_PACKAGE_PHASE_FLAG="firstboot_packages_extracting"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/firstbootLaneCommon.sh
# This is a service to unpack archives that are preformatted to land in the right place.
# Themes and preMenu have to be unpacked before the menu is displayed; preCmd holds
# what games need before cmd_to_run. Every lane unpacks in the foreground.

UNPACK_HAD_FAILURE=0
RUN_MODE="all"
FIRSTBOOT_ARCHIVE_TOTAL="${SPRUCE_FIRSTBOOT_ARCHIVE_TOTAL:-0}"
FIRSTBOOT_ARCHIVE_COMPLETED="${SPRUCE_FIRSTBOOT_ARCHIVE_COMPLETED:-0}"

write_unpack_state() {
    state_value="$1"
    reason_value="$2"
    pid_value="$3"
    tmp_state="${STATE_FILE}.tmp.$$"

    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    {
        printf 'state=%s\n' "$state_value"
        printf 'run_mode=%s\n' "$RUN_MODE"
        printf 'pid=%s\n' "${pid_value:-}"
        printf 'updated_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'reason=%s\n' "${reason_value:-}"
    } > "$tmp_state"
    mv -f "$tmp_state" "$STATE_FILE"
}

exit_with_state() {
    state_value="$1"
    state_reason="$2"
    exit_code="${3:-0}"
    log_line_1="$4"
    log_line_2="$5"
    pid_value="${6:-}"

    write_unpack_state "$state_value" "$state_reason" "$pid_value"
    [ -n "$log_line_1" ] && log_message "$log_line_1"
    [ -n "$log_line_2" ] && log_message "$log_line_2"
    exit "$exit_code"
}

queue_has_archive() {
    dir="$1"
    [ -n "$(find "$dir" -maxdepth 1 -name '*.7z' | head -n 1)" ]
}

run_mode_is_firstboot_theme_phase() {
    [ "$RUN_MODE" = "firstboot_theme_phase" ]
}

archive_firstboot_ui_requested() {
    [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ] || return 1
}

archive_prepare_firstboot_progress() {
    archive_firstboot_ui_requested || return 1

    if [ "$FIRSTBOOT_ARCHIVE_TOTAL" -le 0 ] 2>/dev/null; then
        FIRSTBOOT_ARCHIVE_TOTAL=$((FIRSTBOOT_ARCHIVE_COMPLETED + $(firstboot_progress_count_archives_matching "$THEME_DIR" '*.7z')))
    fi

    [ "$FIRSTBOOT_ARCHIVE_TOTAL" -gt 0 ] 2>/dev/null
}

archive_show_firstboot_progress() {
    archive_prepare_firstboot_progress || return 0
    firstboot_progress_show "$FIRSTBOOT_ARCHIVE_COMPLETED" "$FIRSTBOOT_ARCHIVE_TOTAL"
}

archive_advance_firstboot_progress() {
    archive_prepare_firstboot_progress || return 0
    FIRSTBOOT_ARCHIVE_COMPLETED=$((FIRSTBOOT_ARCHIVE_COMPLETED + 1))
    archive_show_firstboot_progress
}

log_firstboot_theme_archive_status() {
    label="$1"
    status="$2"
    archive_name="$3"
    percent="$(calculate_progress_percent "$FIRSTBOOT_ARCHIVE_COMPLETED" "$FIRSTBOOT_ARCHIVE_TOTAL")"

    log_message "Unpacker: firstboot_theme_archive label=$label status=$status archive=$archive_name progress=${percent}% completed=$FIRSTBOOT_ARCHIVE_COMPLETED total=$FIRSTBOOT_ARCHIVE_TOTAL"
}

queue_empty_for_mode() {
    if run_mode_is_firstboot_theme_phase; then
        ! queue_has_archive "$THEME_DIR"
        return
    fi

    ! queue_has_archive "$THEME_DIR" &&
    ! queue_has_archive "$ARCHIVE_DIR/preMenu" &&
    ! queue_has_archive "$ARCHIVE_DIR/preCmd"
}

parse_startup_args() {
    if [ -n "$1" ]; then
        RUN_MODE="$1"
    fi
}

wait_for_firstboot_package_phase() {
    if flag_check "$FIRSTBOOT_PACKAGE_PHASE_FLAG"; then
        while flag_check "$FIRSTBOOT_PACKAGE_PHASE_FLAG"; do
            sleep 0.1
        done
    fi
}

log_message "Unpacker: Script started"

# Process command line arguments
parse_startup_args "${1:-}"
wait_for_firstboot_package_phase
write_unpack_state "running" "startup" ""

# Function to display which archive is being unpacked
display_unpack_status() {
    section_label="$1"
    detail_line="$2"
    hold_seconds="${3:-0}"

    start_pyui_message_writer
    if archive_prepare_firstboot_progress; then
        :
    elif [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ]; then
        display_image_and_text "$ICON" 35 25 "Sprucing up your device...\nUnpacking ${section_label}\n${detail_line}" 75
    else
        display_image_and_text "$ICON" 35 25 "Unpacking ${section_label}\n${detail_line}" 75
    fi
    if [ "$hold_seconds" -gt 0 ]; then
        sleep "$hold_seconds"
    fi
}

# Function to unpack archives from a specified directory
unpack_archives() {
    dir="$1"
    section_label="$2"
    section_delay_applied=0

    [ -z "$section_label" ] && section_label="archives"

    for archive in "$dir"/*.7z; do
        if [ -f "$archive" ]; then
            archive_name=$(basename "$archive" .7z)
            section_hold=0
            if [ "$section_delay_applied" -eq 0 ]; then
                section_hold=2
                section_delay_applied=1
            fi
            display_unpack_status "$section_label" "$archive_name.7z" "$section_hold"
            if run_mode_is_firstboot_theme_phase; then
                log_firstboot_theme_archive_status "$section_label" "start" "$archive_name.7z"
            fi

            # Judge the members the way 7zr will extract them: it drops a
            # leading "/" and empty path components, so an archive built with
            # absolute paths (xmb.7z ships "/mnt/SDCARD/..." members) or a
            # "mnt/" directory entry (overlays_1024x768.7z) lands under
            # /mnt/SDCARD just like a plain "mnt/SDCARD/..." one. ".."
            # components are refused outright.
            member_paths=$(7zr l -slt "$archive" 2>/dev/null | sed -n 's/^Path = //p' | sed '1d' | tr -s '/' | sed 's#^/##; s#/$##')
            if [ -n "$member_paths" ] &&
                ! printf '%s\n' "$member_paths" | grep -qvE '^mnt(/SDCARD(/.*)?)?$' &&
                ! printf '%s\n' "$member_paths" | grep -qE '(^|/)\.\.(/|$)'; then
                if 7zr x -aoa "$archive" -o/; then
                    rm -f "$archive"
                    log_message "Unpacker: Unpacked and removed: $archive_name.7z"
                    archive_status="success"
                else
                    UNPACK_HAD_FAILURE=1
                    log_message "Unpacker: Failed to unpack: $archive_name.7z"
                    archive_status="failed"
                fi
            else
                log_message "Unpacker: Skipped unpacking: $archive_name.7z (incorrect folder structure)"
                archive_status="skipped"
            fi

            archive_advance_firstboot_progress
            if run_mode_is_firstboot_theme_phase; then
                log_firstboot_theme_archive_status "$section_label" "$archive_status" "$archive_name.7z"
            fi
        fi
    done
}

# Quick check for .7z files in relevant directories
if [ "$RUN_MODE" = "all" ] &&
    ! queue_has_archive "$ARCHIVE_DIR/preCmd" &&
    ! queue_has_archive "$ARCHIVE_DIR/preMenu" &&
    ! queue_has_archive "$THEME_DIR"; then
    exit_with_state \
        "complete" "queue-empty" \
        "0" \
        "Unpacker: No .7z files found to unpack. Exiting." \
        "Unpacker: Finished running"
fi

if run_mode_is_firstboot_theme_phase &&
    ! queue_has_archive "$THEME_DIR"; then
    exit_with_state \
        "complete" "queue-empty-firstboot-theme-phase" \
        "0" \
        "Unpacker: No theme .7z files found to unpack. Exiting." \
        "Unpacker: Finished running"
fi

log_message "Unpacker: Starting theme and archive unpacking process"

run_mode_all() {
    unpack_archives "$THEME_DIR" "Themes"
    unpack_archives "$ARCHIVE_DIR/preMenu" "Pre-menu content"
    unpack_archives "$ARCHIVE_DIR/preCmd" "System content"
}

run_mode_firstboot_theme_phase() {
    # firstboot.sh owns when this phase runs; archiveUnpacker owns the extraction mechanics.
    write_unpack_state "running" "firstboot-theme-phase-active" "$$"
    archive_prepare_firstboot_progress || true
    log_message "Unpacker: firstboot theme archive plan completed=$FIRSTBOOT_ARCHIVE_COMPLETED total=$FIRSTBOOT_ARCHIVE_TOTAL"
    unpack_archives "$THEME_DIR" "Themes"
}

dispatch_run_mode() {
    case "$RUN_MODE" in
    "all") handler="run_mode_all" ;;
    "firstboot_theme_phase") handler="run_mode_firstboot_theme_phase" ;;
    *)
        exit_with_state \
            "failed_resumable" "invalid-run-mode" \
            "1" \
            "Unpacker: Invalid run mode specified: $RUN_MODE"
        ;;
    esac

    "$handler"
}

dispatch_run_mode

if [ "$UNPACK_HAD_FAILURE" -ne 0 ]; then
    exit_with_state \
        "failed_resumable" "archive-extract-failure" \
        "1" \
        "Unpacker: Incomplete due to extraction failures; resumable state persisted."
fi

if queue_empty_for_mode; then
    exit_with_state \
        "complete" "queue-empty" \
        "0" \
        "Unpacker: Finished running"
else
    exit_with_state \
        "failed_resumable" "queue-not-empty" \
        "1" \
        "Unpacker: Incomplete queue detected; resumable state persisted."
fi
