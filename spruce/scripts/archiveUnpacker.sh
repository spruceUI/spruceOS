#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"
ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"
STATE_FILE="/mnt/SDCARD/Saves/spruce/unpacker_state"
PRECMD_PID_FILE="/mnt/SDCARD/spruce/flags/unpacker_precmd.pid"
HANDOFF_FLAG="unpacker_handoff_pre_cmd"
FIRSTBOOT_PACKAGE_PHASE_FLAG="firstboot_packages_extracting"
SYSTEM_EMIT="${SYSTEM_EMIT:-/mnt/SDCARD/spruce/scripts/system-emit}"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# This is a service to unpack archives that are preformatted to land in the right place.
# Since some files need to be available before the menu is displayed, we need to unpack them before
# the menu is displayed so that's one mode.
# The other mode is to unpack archives needed before the command_to_run, this is used for preCmd.

# This can be called with a "pre_cmd" argument to run over preCmd only.
# On firstboot this now runs fully in the foreground; on non-firstboot paths,
# pre_cmd may still hand off to a background worker when safe.

SKIP_SILENT_CLEANUP=0
UNPACK_HAD_FAILURE=0
HANDOFF_BACKGROUND=0
RUN_MODE="all"
SILENT_STATE="0"
FORCE_FOREGROUND_PRECMD="${UNPACKER_FORCE_FOREGROUND_PRECMD:-0}"
TRACE_FINAL_STATE="FINALIZED"
TRACE_FINAL_REASON="normal-exit"
TRACE_FINALIZED=0

emit_archive_trace_finalize() {
    [ "$TRACE_FINALIZED" = "1" ] && return 0
    "$SYSTEM_EMIT" process-finalize archiveUnpacker "archiveUnpacker.sh" "$TRACE_FINAL_STATE" "reason=$TRACE_FINAL_REASON run_mode=$RUN_MODE silent_state=$SILENT_STATE" || true
    TRACE_FINALIZED=1
}

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

set_trace_outcome() {
    TRACE_FINAL_STATE="$1"
    TRACE_FINAL_REASON="$2"
}

exit_with_state() {
    state_value="$1"
    state_reason="$2"
    trace_state="$3"
    trace_reason="$4"
    exit_code="${5:-0}"
    log_line_1="$6"
    log_line_2="$7"
    pid_value="${8:-}"

    write_unpack_state "$state_value" "$state_reason" "$pid_value"
    set_trace_outcome "$trace_state" "$trace_reason"
    [ -n "$log_line_1" ] && log_message "$log_line_1"
    [ -n "$log_line_2" ] && log_message "$log_line_2"
    exit "$exit_code"
}

exit_with_trace_only() {
    trace_state="$1"
    trace_reason="$2"
    exit_code="${3:-0}"
    log_line="$4"

    set_trace_outcome "$trace_state" "$trace_reason"
    [ -n "$log_line" ] && log_message "$log_line"
    exit "$exit_code"
}

queue_has_archive() {
    dir="$1"
    [ -n "$(find "$dir" -maxdepth 1 -name '*.7z' | head -n 1)" ]
}

queue_empty_for_mode() {
    if [ "$RUN_MODE" = "themes_only" ]; then
        ! queue_has_archive "$THEME_DIR"
        return
    fi

    if [ "$RUN_MODE" = "pre_cmd" ]; then
        ! queue_has_archive "$ARCHIVE_DIR/preCmd"
        return
    fi

    ! queue_has_archive "$THEME_DIR" &&
    ! queue_has_archive "$ARCHIVE_DIR/preMenu" &&
    ! queue_has_archive "$ARCHIVE_DIR/preCmd"
}

cleanup() {
    if [ "$RUN_MODE" = "pre_cmd" ]; then
        rm -f "$PRECMD_PID_FILE"
    fi

    if [ "$SKIP_SILENT_CLEANUP" = "1" ]; then
        "$SYSTEM_EMIT" process archiveUnpacker "CLEANUP_SKIP_SILENT_LOCK_REMOVE" "archiveUnpacker.sh/cleanup" "handoff owns silentUnpacker lock" || true
        return
    fi

    "$SYSTEM_EMIT" process archiveUnpacker "CLEANUP_REMOVE_SILENT_LOCK" "archiveUnpacker.sh/cleanup" "removing silentUnpacker lock" || true
    flag_remove "silentUnpacker"
}

archive_exit_handler() {
    cleanup
    emit_archive_trace_finalize
}

parse_startup_args() {
    arg1="$1"
    arg2="$2"

    if [ "$arg1" = "--silent" ]; then
        flag_add "silentUnpacker" --tmp
        SILENT_STATE="1"
        [ -n "$arg2" ] && RUN_MODE="$arg2"
    elif [ -n "$arg1" ]; then
        RUN_MODE="$arg1"
    fi
}

consume_handoff_token_if_present() {
    arg1="$1"
    arg2="$2"

    if [ "$arg1" = "--silent" ] && [ "$arg2" = "pre_cmd" ] && flag_check "$HANDOFF_FLAG"; then
        flag_remove "$HANDOFF_FLAG"
        "$SYSTEM_EMIT" process archiveUnpacker "HANDOFF_TOKEN_CONSUMED" "archiveUnpacker.sh/startup" "consumed silent pre_cmd handoff token" || true
    fi
}

wait_for_firstboot_package_phase() {
    wait_loops=0
    if flag_check "$FIRSTBOOT_PACKAGE_PHASE_FLAG"; then
        "$SYSTEM_EMIT" process archiveUnpacker "WAIT_FIRSTBOOT_PACKAGE_PHASE_BEGIN" "archiveUnpacker.sh/startup" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG" || true
        while flag_check "$FIRSTBOOT_PACKAGE_PHASE_FLAG"; do
            wait_loops=$((wait_loops + 1))
            if [ $((wait_loops % 50)) -eq 0 ]; then
                "$SYSTEM_EMIT" process archiveUnpacker "WAIT_FIRSTBOOT_PACKAGE_PHASE_LOOP" "archiveUnpacker.sh/startup" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG loops=$wait_loops" || true
            fi
            sleep 0.1
        done
        "$SYSTEM_EMIT" process archiveUnpacker "WAIT_FIRSTBOOT_PACKAGE_PHASE_END" "archiveUnpacker.sh/startup" "flag=$FIRSTBOOT_PACKAGE_PHASE_FLAG loops=$wait_loops" || true
    fi
}

"$SYSTEM_EMIT" process-init archiveUnpacker "archiveUnpacker.sh" "argv1=${1:-} argv2=${2:-}" || true

# Guard against overlapping unpack workers.
# A --silent pre_cmd worker is allowed to enter only when an explicit parent handoff flag exists.
if flag_check "silentUnpacker"; then
    if [ "$1" = "--silent" ] && [ "$2" = "pre_cmd" ] && flag_check "$HANDOFF_FLAG"; then
        flag_remove "$HANDOFF_FLAG"
        "$SYSTEM_EMIT" process archiveUnpacker "HANDOFF_ACCEPTED" "archiveUnpacker.sh/startup-guard" "accepted silent pre_cmd handoff" || true
    else
        log_message "Unpacker: Another silent unpacker is running, exiting" -v
        "$SYSTEM_EMIT" process archiveUnpacker "EARLY_EXIT_SILENT_LOCK_EXISTS" "archiveUnpacker.sh/startup-guard" "silentUnpacker lock exists" || true
        TRACE_FINAL_STATE="SKIPPED_LOCK"
        TRACE_FINAL_REASON="existing-silentUnpacker-lock"
        emit_archive_trace_finalize
        exit 0
    fi
fi

log_message "Unpacker: Script started"

# Set trap for script exit
trap archive_exit_handler EXIT

# Process command line arguments
parse_startup_args "${1:-}" "${2:-}"
consume_handoff_token_if_present "${1:-}" "${2:-}"
wait_for_firstboot_package_phase

if flag_check "silentUnpacker"; then
    SILENT_STATE="1"
fi
"$SYSTEM_EMIT" process archiveUnpacker "STARTUP_MODE" "archiveUnpacker.sh/startup" "run_mode=$RUN_MODE silent_state=$SILENT_STATE" || true
write_unpack_state "running" "startup" ""

# Function to display text if not in silent mode
display_if_not_silent() {
    section_label="$1"
    detail_line="$2"
    hold_seconds="${3:-0}"

    if flag_check "silentUnpacker"; then
        return 0
    fi

    start_pyui_message_writer
    "$SYSTEM_EMIT" process archiveUnpacker "UI_NOTIFY_ARCHIVE" "archiveUnpacker.sh/display_if_not_silent" "section=${section_label:-unknown} detail=${detail_line:-unknown}" || true
    if [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ]; then
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
    flag_name="$2"
    section_label="$3"
    found_count=0
    success_count=0
    fail_count=0
    skip_count=0
    section_delay_applied=0

    [ -z "$section_label" ] && section_label="archives"

    [ -n "$flag_name" ] && flag_add "$flag_name" --tmp
    "$SYSTEM_EMIT" process archiveUnpacker "FLAG_SET" "archiveUnpacker.sh/unpack_archives" "flag=${flag_name:-none} dir=$dir section=$section_label" || true
    "$SYSTEM_EMIT" process archiveUnpacker "BEGIN_DIR" "archiveUnpacker.sh/unpack_archives" "dir=$dir" || true

    for archive in "$dir"/*.7z; do
        if [ -f "$archive" ]; then
            found_count=$((found_count + 1))
            archive_name=$(basename "$archive" .7z)
            "$SYSTEM_EMIT" process archiveUnpacker "ARCHIVE_CANDIDATE" "archiveUnpacker.sh/unpack_archives" "archive=$archive_name.7z dir=$dir" || true
            section_hold=0
            if [ "$section_delay_applied" -eq 0 ]; then
                section_hold=2
                section_delay_applied=1
            fi
            display_if_not_silent "$section_label" "$archive_name.7z" "$section_hold"

            if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
                if 7zr x -aoa "$archive" -o/; then
                    rm -f "$archive"
                    success_count=$((success_count + 1))
                    log_message "Unpacker: Unpacked and removed: $archive_name.7z"
                else
                    fail_count=$((fail_count + 1))
                    UNPACK_HAD_FAILURE=1
                    log_message "Unpacker: Failed to unpack: $archive_name.7z"
                fi
            else
                skip_count=$((skip_count + 1))
                log_message "Unpacker: Skipped unpacking: $archive_name.7z (incorrect folder structure)"
            fi
        fi
    done

    "$SYSTEM_EMIT" process archiveUnpacker "SUMMARY" "archiveUnpacker.sh/unpack_archives" "dir=$dir found=$found_count success=$success_count failed=$fail_count skipped=$skip_count" || true
    [ -n "$flag_name" ] && flag_remove "$flag_name"
    "$SYSTEM_EMIT" process archiveUnpacker "FLAG_CLEARED" "archiveUnpacker.sh/unpack_archives" "flag=${flag_name:-none} dir=$dir" || true
}

# Quick check for .7z files in relevant directories
if [ "$RUN_MODE" = "all" ] &&
    ! queue_has_archive "$ARCHIVE_DIR/preCmd" &&
    ! queue_has_archive "$ARCHIVE_DIR/preMenu" &&
    ! queue_has_archive "$THEME_DIR"; then
    "$SYSTEM_EMIT" process archiveUnpacker "QUEUE_EMPTY_FAST_PATH" "archiveUnpacker.sh/startup" "no archives in themes/preMenu/preCmd" || true
    exit_with_state \
        "complete" "queue-empty" \
        "COMPLETE" "queue-empty-fast-path" \
        "0" \
        "Unpacker: No .7z files found to unpack. Exiting." \
        "Unpacker: Finished running"
fi

if [ "$RUN_MODE" = "themes_only" ] &&
    ! queue_has_archive "$THEME_DIR"; then
    "$SYSTEM_EMIT" process archiveUnpacker "QUEUE_EMPTY_THEMES_FAST_PATH" "archiveUnpacker.sh/startup" "no archives in themes" || true
    exit_with_state \
        "complete" "queue-empty-themes" \
        "COMPLETE" "queue-empty-themes-fast-path" \
        "0" \
        "Unpacker: No theme .7z files found to unpack. Exiting." \
        "Unpacker: Finished running"
fi

log_message "Unpacker: Starting theme and archive unpacking process"

run_mode_all() {
    unpack_archives "$THEME_DIR" "" "Themes"
    unpack_archives "$ARCHIVE_DIR/preMenu" "pre_menu_unpacking" "Pre-menu content"
    if [ "$FORCE_FOREGROUND_PRECMD" = "1" ] || flag_check "save_active"; then
        if [ "$FORCE_FOREGROUND_PRECMD" = "1" ]; then
            "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_FOREGROUND_FORCED" "archiveUnpacker.sh/run_mode_all" "forced foreground pre_cmd in sequential firstboot" || true
        else
            "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_FOREGROUND_SAVE_ACTIVE" "archiveUnpacker.sh/run_mode_all" "save_active=1" || true
        fi
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking" "System content"
    else
        "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_HANDOFF_BACKGROUND" "archiveUnpacker.sh/run_mode_all" "save_active=0" || true
        flag_add "$HANDOFF_FLAG" --tmp
        /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent pre_cmd &
        handoff_pid="$!"
        HANDOFF_BACKGROUND=1
        echo "$handoff_pid" > "$PRECMD_PID_FILE"
        write_unpack_state "running" "handoff-pre_cmd" "$handoff_pid"
        SKIP_SILENT_CLEANUP=1
        "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_HANDOFF_SPAWNED" "archiveUnpacker.sh/run_mode_all" "pid=$handoff_pid" || true
    fi
}

run_mode_pre_cmd() {
    "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_MODE_FOREGROUND" "archiveUnpacker.sh/run_mode_pre_cmd" "foreground pre_cmd run" || true
    echo "$$" > "$PRECMD_PID_FILE"
    write_unpack_state "running" "pre_cmd-active" "$$"
    unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking" "System content"
}

run_mode_themes_only() {
    "$SYSTEM_EMIT" process archiveUnpacker "THEMES_ONLY_MODE_FOREGROUND" "archiveUnpacker.sh/run_mode_themes_only" "foreground themes-only run" || true
    write_unpack_state "running" "themes-only-active" "$$"
    unpack_archives "$THEME_DIR" "" "Themes"
}

dispatch_run_mode() {
    case "$RUN_MODE" in
    "all")
        run_mode_all
        ;;
    "themes_only")
        run_mode_themes_only
        ;;
    "pre_cmd")
        run_mode_pre_cmd
        ;;
    *)
        exit_with_state \
            "failed_resumable" "invalid-run-mode" \
            "FAILED" "invalid-run-mode" \
            "1" \
            "Unpacker: Invalid run mode specified"
        ;;
    esac
}

dispatch_run_mode

if [ "$HANDOFF_BACKGROUND" = "1" ]; then
    exit_with_trace_only \
        "HANDOFF_BACKGROUND" "pre_cmd-background-handoff" \
        "0" \
        "Unpacker: Foreground phases finished; pre_cmd handed off to background worker."
fi

if [ "$UNPACK_HAD_FAILURE" -ne 0 ]; then
    exit_with_state \
        "failed_resumable" "archive-extract-failure" \
        "FAILED" "archive-extract-failure" \
        "1" \
        "Unpacker: Incomplete due to extraction failures; resumable state persisted."
fi

if queue_empty_for_mode; then
    exit_with_state \
        "complete" "queue-empty" \
        "COMPLETE" "queue-empty" \
        "0" \
        "Unpacker: Finished running"
else
    exit_with_state \
        "failed_resumable" "queue-not-empty" \
        "FAILED" "queue-not-empty" \
        "1" \
        "Unpacker: Incomplete queue detected; resumable state persisted."
fi
