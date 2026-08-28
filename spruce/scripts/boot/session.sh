#!/bin/sh
# Spruce boot session supervisor.
#
# Runs runtime.sh on behalf of the rootfs stub (the Flip's runmiyoo.sh, the
# Miniloong's S50spruce) and turns "runtime.sh died" from a black screen into
# a decision: try again, or hand the device to the vendor UI. Everything here
# lives on the card so it ships with releases; the stub in the rootfs stays
# small and stays put. Design: ~/ai/CFW/Miniloong/research/
# rk3566-boot-bootstrap-phase1-20260828.md (section 3.2).
#
# Contract with the stub, expressed only through the exit status:
#   0  clean exit (a shutdown is in progress, or runtime returned during one)
#   1  refused: disable flag present, or preflight failed
#   2  crash-loop guard tripped (disable flag written for the next boot)
#   3  exit-to-stock requested by the user
# If device_stock_ui_command prints a command, that command is exec'd instead
# of returning 1/2/3, because the stub cannot do it (the Flip's v1 runmiyoo.sh
# just exits when this returns). Stubs that own the hand-off print nothing.
#
# "Disabled" is a positive flag, never a missing file: repairSD.sh and the
# Flip's miyoo355/app/MainUI installer re-create a missing updater and reboot,
# so removing files to disable Spruce would bounce forever.
#
# Every path is overridable so the host unit tests can run this script
# against a fake card; the defaults are the device layout.

SD="${SPRUCE_BOOT_SD:-/mnt/SDCARD}"
TMP="${SPRUCE_BOOT_TMP:-/tmp}"
SCRIPTS="$SD/spruce/scripts"
FLAGS="$SD/spruce/flags"
LOG="${SPRUCE_BOOT_LOG:-$SD/Saves/spruce/boot-session.log}"
CRASH_STATE="$FLAGS/boot_crash_state"
DISABLE_FLAG="$FLAGS/boot_to_stock.lock"
EXIT_TO_STOCK="$TMP/exit_to_stock.lock"
CLEAN_EXIT="$TMP/boot_clean_exit.lock"
SHUTTING_DOWN="$TMP/shutting_down.lock"
CRASH_WINDOW="${SPRUCE_BOOT_CRASH_WINDOW:-120}"
CRASH_THRESHOLD="${SPRUCE_BOOT_CRASH_THRESHOLD:-3}"
RUNTIME="${SPRUCE_BOOT_RUNTIME:-$SCRIPTS/runtime.sh}"
HELPERS="${SPRUCE_BOOT_HELPERS:-$SCRIPTS/helperFunctions.sh}"

export SPRUCE_BOOT_SESSION=1

log() {
    _dir="${LOG%/*}"
    [ "$_dir" != "$LOG" ] && mkdir -p "$_dir" 2>/dev/null
    printf '[%s] session: %s\n' "$(date '+%F %T' 2>/dev/null || echo unknown)" "$*" >>"$LOG" 2>/dev/null
}

now() {
    date '+%s' 2>/dev/null || echo 0
}

# The stock UI command comes from the platform's device functions, which need
# helperFunctions.sh sourced. Sourcing that file is the first thing that can
# go wrong on a broken card, so it is syntax-checked first and sourced in a
# way that cannot take the supervisor down with it.
stock_ui_command() {
    [ -n "${SPRUCE_BOOT_STOCK_CMD+x}" ] && { printf '%s' "$SPRUCE_BOOT_STOCK_CMD"; return 0; }
    [ -f "$HELPERS" ] || return 0
    sh -n "$HELPERS" 2>/dev/null || return 0
    ( . "$HELPERS" >/dev/null 2>&1; command -v device_stock_ui_command >/dev/null 2>&1 && device_stock_ui_command ) 2>/dev/null
}

hand_to_stock() {
    _status="$1"
    _reason="$2"
    log "$_reason; handing this boot to stock (status $_status)"
    _cmd="$(stock_ui_command)"
    if [ -n "$_cmd" ]; then
        log "exec stock ui: $_cmd"
        exec sh -c "$_cmd"
    fi
    exit "$_status"
}

preflight() {
    if [ -e "$DISABLE_FLAG" ]; then
        log "disable flag present: $DISABLE_FLAG"
        return 1
    fi
    for _f in "$RUNTIME" "$HELPERS"; do
        if [ ! -f "$_f" ]; then
            log "preflight: missing $_f"
            return 1
        fi
    done
    if ! sh -n "$RUNTIME" 2>/dev/null; then
        log "preflight: $RUNTIME does not parse"
        return 1
    fi
    mkdir -p "$FLAGS" 2>/dev/null
    if ! ( : >"$FLAGS/.boot_session_writetest" ) 2>/dev/null; then
        log "preflight: $FLAGS is not writable (card read-only?)"
        return 1
    fi
    rm -f "$FLAGS/.boot_session_writetest" 2>/dev/null
    return 0
}

# Three unclean runtime exits inside the window disable the next boot. A clean
# exit resets the count. State lives on the card so it survives the reboot the
# user is about to do in frustration; /tmp would forget it.
crash_guard() {
    if [ -f "$CLEAN_EXIT" ]; then
        rm -f "$CLEAN_EXIT" "$CRASH_STATE" 2>/dev/null
        log "clean exit seen; crash counter reset"
        return 0
    fi
    _now="$(now)"
    [ "$_now" -gt 0 ] 2>/dev/null || { log "crash guard skipped: no clock"; return 0; }
    _first="$_now"
    _count=0
    if [ -f "$CRASH_STATE" ]; then
        read -r _first _count <"$CRASH_STATE" 2>/dev/null || { _first="$_now"; _count=0; }
    fi
    case "$_first" in *[!0-9]*|'') _first="$_now" ;; esac
    case "$_count" in *[!0-9]*|'') _count=0 ;; esac
    _age=$((_now - _first))
    if [ "$_age" -lt 0 ] || [ "$_age" -gt "$CRASH_WINDOW" ]; then
        _first="$_now"
        _count=1
    else
        _count=$((_count + 1))
    fi
    printf '%s %s\n' "$_first" "$_count" >"$CRASH_STATE" 2>/dev/null
    if [ "$_count" -ge "$CRASH_THRESHOLD" ]; then
        log "crash-loop guard tripped: $_count starts within ${CRASH_WINDOW}s"
        : >"$DISABLE_FLAG" 2>/dev/null
        rm -f "$CRASH_STATE" 2>/dev/null
        return 1
    fi
    return 0
}

preflight || hand_to_stock 1 "preflight failed"

log "starting session (platform hook: ${SPRUCE_BOOT_PLATFORM:-unset})"
while :; do
    crash_guard || hand_to_stock 2 "crash-loop guard"
    cd "$SCRIPTS" 2>/dev/null || hand_to_stock 1 "cannot cd to $SCRIPTS"
    log "starting $RUNTIME"
    "$RUNTIME"
    _rc=$?
    if [ -e "$SHUTTING_DOWN" ]; then
        log "runtime returned rc=$_rc during shutdown; clean exit"
        rm -f "$CRASH_STATE" 2>/dev/null
        exit 0
    fi
    if [ -e "$EXIT_TO_STOCK" ]; then
        rm -f "$EXIT_TO_STOCK" "$CRASH_STATE" 2>/dev/null
        hand_to_stock 3 "exit-to-stock requested"
    fi
    log "runtime exited rc=$_rc; restarting"
    sleep 1
done
