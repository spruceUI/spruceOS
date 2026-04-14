#!/bin/sh

FIRSTBOOT_PROGRESS_STATE_FILE="${FIRSTBOOT_PROGRESS_STATE_FILE:-/tmp/firstboot_extract_progress_state}"

firstboot_progress_write_state() {
    total_value="$1"
    completed_value="$2"
    tmp_state="${FIRSTBOOT_PROGRESS_STATE_FILE}.$$"

    {
        printf 'total=%s\n' "$total_value"
        printf 'completed=%s\n' "$completed_value"
    } > "$tmp_state"
    mv -f "$tmp_state" "$FIRSTBOOT_PROGRESS_STATE_FILE"
}

firstboot_progress_read_value() {
    key="$1"

    if [ -f "$FIRSTBOOT_PROGRESS_STATE_FILE" ]; then
        sed -n "s/^${key}=//p" "$FIRSTBOOT_PROGRESS_STATE_FILE" | head -n 1
    fi
}

firstboot_progress_clear_state() {
    rm -f "$FIRSTBOOT_PROGRESS_STATE_FILE"
}

firstboot_progress_count_archives_matching() {
    dir="$1"
    pattern="$2"
    count=0

    for archive in "$dir"/$pattern; do
        [ -f "$archive" ] || continue
        count=$((count + 1))
    done

    printf '%s\n' "$count"
}

firstboot_progress_show() {
    completed_value="$1"
    total_value="$2"
    logo_path="$3"

    [ "$total_value" -gt 0 ] || return 0
    firstboot_progress_write_state "$total_value" "$completed_value"
    if [ -n "$logo_path" ]; then
        display_firstboot_extract_progress "$completed_value" "$total_value" "$logo_path"
    else
        display_firstboot_extract_progress "$completed_value" "$total_value"
    fi
}

firstboot_progress_prepare_unpacker_context() {
    firstboot_ui="$1"

    FIRSTBOOT_PROGRESS_CONTEXT_UI="${firstboot_ui:-0}"
    FIRSTBOOT_PROGRESS_CONTEXT_TOTAL=0
    FIRSTBOOT_PROGRESS_CONTEXT_COMPLETED=0

    [ "$FIRSTBOOT_PROGRESS_CONTEXT_UI" = "1" ] || return 0

    FIRSTBOOT_PROGRESS_CONTEXT_TOTAL="$(firstboot_progress_read_value total)"
    FIRSTBOOT_PROGRESS_CONTEXT_COMPLETED="$(firstboot_progress_read_value completed)"
}

firstboot_progress_finalize_unpacker_context() {
    [ "${1:-0}" = "1" ] || return 0
    firstboot_progress_clear_state
}
