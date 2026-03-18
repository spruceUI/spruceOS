#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"
ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"
STATE_FILE="/mnt/SDCARD/Saves/spruce/unpacker_state"
PRECMD_PID_FILE="/mnt/SDCARD/spruce/flags/unpacker_precmd.pid"
HANDOFF_FLAG="unpacker_handoff_pre_cmd"
SYSTEM_EMIT="${SYSTEM_EMIT:-/mnt/SDCARD/spruce/scripts/system-emit}"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# This is a service to unpack archives that are preformatted to land in the right place.
# Since some files need to be available before the menu is displayed, we need to unpack them before
# the menu is displayed so that's one mode.
# The other mode is to unpack archives needed before the command_to_run, this is used for preCmd.

# This can be called with a "pre_cmd" argument to run over preCmd only.
# Typically you'd use that for any unpacking process since we don't want extraction to happen in the background.
# It's rather resource heavy and we don't want to leave it running in the background.

SKIP_SILENT_CLEANUP=0
UNPACK_HAD_FAILURE=0
HANDOFF_BACKGROUND=0
RUN_MODE="all"
SILENT_STATE="0"
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

queue_has_archive() {
    dir="$1"
    [ -n "$(find "$dir" -maxdepth 1 -name '*.7z' | head -n 1)" ]
}

queue_empty_for_mode() {
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
if [ "$1" = "--silent" ]; then
    flag_add "silentUnpacker" --tmp
    SILENT_STATE="1"
    [ -n "$2" ] && RUN_MODE="$2"
elif [ -n "$1" ]; then
    RUN_MODE="$1"
fi

if [ "$1" = "--silent" ] && [ "$2" = "pre_cmd" ] && flag_check "$HANDOFF_FLAG"; then
    flag_remove "$HANDOFF_FLAG"
    "$SYSTEM_EMIT" process archiveUnpacker "HANDOFF_TOKEN_CONSUMED" "archiveUnpacker.sh/startup" "consumed silent pre_cmd handoff token" || true
fi

if flag_check "silentUnpacker"; then
    SILENT_STATE="1"
fi
"$SYSTEM_EMIT" process archiveUnpacker "STARTUP_MODE" "archiveUnpacker.sh/startup" "run_mode=$RUN_MODE silent_state=$SILENT_STATE" || true
write_unpack_state "running" "startup" ""

# Function to display text if not in silent mode
display_if_not_silent() {
    show_progress=0
    if ! flag_check "silentUnpacker"; then
        show_progress=1
    elif flag_check "unpacker_ui_visible"; then
        show_progress=1
    fi

    if [ "$show_progress" -eq 1 ]; then
        hold_wait_loops=0
        while flag_check "firstboot_screen_hold"; do
            hold_wait_loops=$((hold_wait_loops + 1))
            if [ "$hold_wait_loops" -ge 300 ]; then
                log_message "Unpacker: firstboot screen hold wait timed out; continuing archive progress UI."
                break
            fi
            sleep 0.1
        done

        start_pyui_message_writer
        "$SYSTEM_EMIT" process archiveUnpacker "UI_NOTIFY_ARCHIVE" "archiveUnpacker.sh/display_if_not_silent" "archive=${archive_name:-unknown}" || true
        display_image_and_text "$ICON" 35 25 "$archive_name archive detected. Unpacking.........." 75
    fi
}

# Function to unpack archives from a specified directory
unpack_archives() {
    dir="$1"
    flag_name="$2"
    found_count=0
    success_count=0
    fail_count=0
    skip_count=0

    [ -n "$flag_name" ] && flag_add "$flag_name" --tmp
    "$SYSTEM_EMIT" process archiveUnpacker "FLAG_SET" "archiveUnpacker.sh/unpack_archives" "flag=${flag_name:-none} dir=$dir" || true
    "$SYSTEM_EMIT" process archiveUnpacker "BEGIN_DIR" "archiveUnpacker.sh/unpack_archives" "dir=$dir" || true

    for archive in "$dir"/*.7z; do
        if [ -f "$archive" ]; then
            found_count=$((found_count + 1))
            archive_name=$(basename "$archive" .7z)
            "$SYSTEM_EMIT" process archiveUnpacker "ARCHIVE_CANDIDATE" "archiveUnpacker.sh/unpack_archives" "archive=$archive_name.7z dir=$dir" || true
            display_if_not_silent

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
    TRACE_FINAL_STATE="COMPLETE"
    TRACE_FINAL_REASON="queue-empty-fast-path"
    write_unpack_state "complete" "queue-empty" ""
    log_message "Unpacker: No .7z files found to unpack. Exiting."
    log_message "Unpacker: Finished running"
    exit 0
fi

log_message "Unpacker: Starting theme and archive unpacking process"

# Process archives based on run mode
case "$RUN_MODE" in
"all")
    unpack_archives "$THEME_DIR"
    unpack_archives "$ARCHIVE_DIR/preMenu" "pre_menu_unpacking"
    if flag_check "save_active"; then
        "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_FOREGROUND_SAVE_ACTIVE" "archiveUnpacker.sh/run_mode_all" "save_active=1" || true
        unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
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
    ;;
"pre_cmd")
    "$SYSTEM_EMIT" process archiveUnpacker "PRECMD_MODE_FOREGROUND" "archiveUnpacker.sh/run_mode_pre_cmd" "foreground pre_cmd run" || true
    echo "$$" > "$PRECMD_PID_FILE"
    write_unpack_state "running" "pre_cmd-active" "$$"
    unpack_archives "$ARCHIVE_DIR/preCmd" "pre_cmd_unpacking"
    ;;
*)
    TRACE_FINAL_STATE="FAILED"
    TRACE_FINAL_REASON="invalid-run-mode"
    write_unpack_state "failed_resumable" "invalid-run-mode" ""
    log_message "Unpacker: Invalid run mode specified"
    exit 1
    ;;
esac

if [ "$HANDOFF_BACKGROUND" = "1" ]; then
    TRACE_FINAL_STATE="HANDOFF_BACKGROUND"
    TRACE_FINAL_REASON="pre_cmd-background-handoff"
    log_message "Unpacker: Foreground phases finished; pre_cmd handed off to background worker."
    exit 0
fi

if [ "$UNPACK_HAD_FAILURE" -ne 0 ]; then
    TRACE_FINAL_STATE="FAILED"
    TRACE_FINAL_REASON="archive-extract-failure"
    write_unpack_state "failed_resumable" "archive-extract-failure" ""
    log_message "Unpacker: Incomplete due to extraction failures; resumable state persisted."
    exit 1
fi

if queue_empty_for_mode; then
    TRACE_FINAL_STATE="COMPLETE"
    TRACE_FINAL_REASON="queue-empty"
    write_unpack_state "complete" "queue-empty" ""
    log_message "Unpacker: Finished running"
else
    TRACE_FINAL_STATE="FAILED"
    TRACE_FINAL_REASON="queue-not-empty"
    write_unpack_state "failed_resumable" "queue-not-empty" ""
    log_message "Unpacker: Incomplete queue detected; resumable state persisted."
    exit 1
fi
