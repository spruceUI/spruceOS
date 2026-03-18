#!/bin/sh

TRACE_ROOT="${TRACE_ROOT:-/mnt/SDCARD/Saves/spruce}"
TRACE_DIR="${TRACE_DIR:-$TRACE_ROOT/trace}"
TRACE_EVENTS_FILE="${TRACE_EVENTS_FILE:-$TRACE_DIR/events.jsonl}"
TRACE_SUMMARY_FILE="${TRACE_SUMMARY_FILE:-$TRACE_DIR/summary.txt}"
TRACE_STATE_FILE="${TRACE_STATE_FILE:-$TRACE_DIR/state.env}"
TRACE_MAX_EVENTS="${TRACE_MAX_EVENTS:-400}"
TRACE_MAX_SUMMARY_LINES="${TRACE_MAX_SUMMARY_LINES:-120}"
POWER_TRACE_DIR="${POWER_TRACE_DIR:-$TRACE_ROOT/power}"
POWER_TRACE_EVENTS_FILE="${POWER_TRACE_EVENTS_FILE:-$POWER_TRACE_DIR/events.jsonl}"
POWER_TRACE_SUMMARY_FILE="${POWER_TRACE_SUMMARY_FILE:-$POWER_TRACE_DIR/summary.txt}"
TRACE_ENABLED="${TRACE_ENABLED:-1}"
POWER_TRACE_ENABLED="${POWER_TRACE_ENABLED:-1}"
AUDIO_TRACE_ENABLED="${AUDIO_TRACE_ENABLED:-1}"
NETWORK_TRACE_ENABLED="${NETWORK_TRACE_ENABLED:-${WIFI_TRACE_ENABLED:-1}}"
BRIGHTNESS_TRACE_ENABLED="${BRIGHTNESS_TRACE_ENABLED:-1}"
PROCESS_TRACE_ENABLED="${PROCESS_TRACE_ENABLED:-1}"
TRACE_GATE_DIR="${TRACE_GATE_DIR:-/tmp/spruce_trace_gates}"
TRACE_STATE_FLUSH_INTERVAL="${TRACE_STATE_FLUSH_INTERVAL:-20}"
TRACE_TRIM_INTERVAL="${TRACE_TRIM_INTERVAL:-20}"
TRACE_FSM_DIR="${TRACE_FSM_DIR:-$TRACE_DIR/fsm}"
TRACE_CACHE_DIR="${TRACE_CACHE_DIR:-/tmp/spruce_trace_cache}"
# Maximum magnitude of a single audio/brightness step before it is flagged
# as a large jump.  Set to 0 to disable the check for that subsystem.
AUDIO_LARGE_JUMP_THRESHOLD="${AUDIO_LARGE_JUMP_THRESHOLD:-5}"
BRIGHTNESS_LARGE_JUMP_THRESHOLD="${BRIGHTNESS_LARGE_JUMP_THRESHOLD:-3}"

trace_state_loaded=0
trace_dirs_ready=0
trace_trim_counter=0
trace_unknown_domain_warned=""
trace_cached_boot_id=""
trace_cached_build_id=""

trace_normalize_subsystem() {
    case "$1" in
        wifi|network|networking)
            printf '%s\n' "networking"
            ;;
        power|audio|brightness)
            printf '%s\n' "$1"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

trace_gate_enabled() {
    subsystem="$(trace_normalize_subsystem "$1")"

    [ "$TRACE_ENABLED" = "0" ] && return 1
    [ -f "$TRACE_GATE_DIR/trace.off" ] && return 1

    case "$subsystem" in
        power)
            [ "$POWER_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/power.off" ] && return 1
            ;;
        audio)
            [ "$AUDIO_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/audio.off" ] && return 1
            ;;
        networking)
            [ "$NETWORK_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/networking.off" ] && return 1
            [ -f "$TRACE_GATE_DIR/wifi.off" ] && return 1
            ;;
        brightness)
            [ "$BRIGHTNESS_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/brightness.off" ] && return 1
            ;;
        process|process-*)
            [ "$PROCESS_TRACE_ENABLED" = "0" ] && return 1
            [ -f "$TRACE_GATE_DIR/process.off" ] && return 1
            ;;
        *)
            case " $trace_unknown_domain_warned " in
                *" $subsystem "*)
                    ;;
                *)
                    trace_unknown_domain_warned="$trace_unknown_domain_warned $subsystem"
                    printf '%s\n' "trace_gate_enabled: unknown subsystem '$subsystem'" >&2
                    ;;
            esac
            return 1
            ;;
    esac

    return 0
}

trace_monotonic_ts() {
    awk '{print $1}' /proc/uptime 2>/dev/null
}

trace_wall_ts() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

trace_boot_id() {
    if [ -z "$trace_cached_boot_id" ]; then
        if [ -r /proc/sys/kernel/random/boot_id ]; then
            trace_cached_boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
        fi
        [ -n "$trace_cached_boot_id" ] || trace_cached_boot_id="boot-unknown"
    fi
    printf '%s\n' "$trace_cached_boot_id"
}

trace_build() {
    if [ -z "$trace_cached_build_id" ]; then
        trace_cached_build_id="$(cat /etc/version 2>/dev/null)"
        [ -n "$trace_cached_build_id" ] || trace_cached_build_id="unknown"
    fi
    printf '%s\n' "$trace_cached_build_id"
}

trace_escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

trace_trim_file() {
    file="$1"
    max_lines="$2"
    [ -f "$file" ] || return 0
    count=$(wc -l < "$file" 2>/dev/null || echo 0)
    if [ "$count" -gt "$max_lines" ]; then
        tail -n "$max_lines" "$file" > "$file.tmp.$$" && mv "$file.tmp.$$" "$file"
    fi
}

trace_cache_state_file() {
    subsystem="$(trace_normalize_subsystem "$1")"
    printf '%s/%s.state\n' "$TRACE_CACHE_DIR" "$subsystem"
}

trace_cache_read_state() {
    cache_file="$(trace_cache_state_file "$1")"
    if [ -r "$cache_file" ]; then
        head -n 1 "$cache_file" 2>/dev/null
    fi
}

trace_cache_write_state() {
    subsystem="$(trace_normalize_subsystem "$1")"
    state="$2"

    case "$state" in
        ''|UNKNOWN|AUTO)
            return 0
            ;;
    esac

    cache_file="$(trace_cache_state_file "$subsystem")"
    mkdir -p "$TRACE_CACHE_DIR" 2>/dev/null || return 0
    printf '%s\n' "$state" > "$cache_file.tmp.$$" && mv "$cache_file.tmp.$$" "$cache_file"
}

trace_load_state() {
    [ "$trace_state_loaded" = "1" ] && return 0
    trace_ensure_dirs
    if [ -f "$TRACE_STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$TRACE_STATE_FILE"
    fi
    [ -n "${trace_seq:-}" ] || trace_seq=0
    trace_state_loaded=1
}

trace_save_state() {
    trace_ensure_dirs
    umask 077
    cat > "$TRACE_STATE_FILE.tmp.$$" <<EOF_STATE
trace_seq="$trace_seq"
EOF_STATE
    mv "$TRACE_STATE_FILE.tmp.$$" "$TRACE_STATE_FILE"
}

trace_ensure_dirs() {
    [ "$trace_dirs_ready" = "1" ] && return 0
    mkdir -p "$TRACE_DIR"
    mkdir -p "$(dirname "$TRACE_EVENTS_FILE")"
    mkdir -p "$(dirname "$TRACE_SUMMARY_FILE")"
    trace_dirs_ready=1
}

trace_next_seq() {
    trace_load_state
    trace_seq=$(( ${trace_seq:-0} + 1 ))
    printf '%s\n' "$trace_seq"

    flush_interval="$TRACE_STATE_FLUSH_INTERVAL"
    case "$flush_interval" in
        ''|*[!0-9]*) flush_interval=20 ;;
    esac
    if [ ! -f "$TRACE_STATE_FILE" ] || [ "$flush_interval" -le 1 ] || [ $((trace_seq % flush_interval)) -eq 0 ]; then
        trace_save_state
    fi
}

trace_emit_core() {
    events_file="$1"
    summary_file="$2"
    max_events="$3"
    max_summary="$4"
    json_line="$5"
    summary_line="$6"

    trace_ensure_dirs
    mkdir -p "$(dirname "$events_file")"
    mkdir -p "$(dirname "$summary_file")"
    printf '%s\n' "$json_line" >> "$events_file"
    printf '%s\n' "$summary_line" >> "$summary_file"

    trace_trim_counter=$((trace_trim_counter + 1))
    trim_interval="$TRACE_TRIM_INTERVAL"
    case "$trim_interval" in
        ''|*[!0-9]*) trim_interval=20 ;;
    esac
    if [ "$trim_interval" -le 1 ] || [ $((trace_trim_counter % trim_interval)) -eq 0 ]; then
        trace_trim_file "$events_file" "$max_events"
        trace_trim_file "$summary_file" "$max_summary"
    fi
}

trace_subsystem_dir() {
    subsystem="$(trace_normalize_subsystem "$1")"
    printf '%s/%s\n' "$TRACE_ROOT" "$subsystem"
}

trace_subsystem_events_file() {
    printf '%s/events.jsonl\n' "$(trace_subsystem_dir "$1")"
}

trace_subsystem_summary_file() {
    printf '%s/summary.txt\n' "$(trace_subsystem_dir "$1")"
}

trace_build_json_line() {
    seq="$1"
    subsystem="$2"
    current_state="$3"
    requested_state="$4"
    source_ref="$5"
    context="$6"
    ts_mono="$7"
    ts_wall="$8"
    boot_session_id="$9"
    platform_id="${10}"
    build_id="${11}"

    printf '{"seq":%s,"subsystem":"%s","current_state":"%s","requested_state":"%s","source":"%s","context":"%s","ts_monotonic":"%s","ts_wall":"%s","boot_session_id":"%s","platform":"%s","build":"%s"}' \
        "$seq" \
        "$(trace_escape_json "$subsystem")" \
        "$(trace_escape_json "$current_state")" \
        "$(trace_escape_json "$requested_state")" \
        "$(trace_escape_json "$source_ref")" \
        "$(trace_escape_json "$context")" \
        "$ts_mono" \
        "$ts_wall" \
        "$boot_session_id" \
        "$platform_id" \
        "$build_id"
}

trace_build_summary_line() {
    ts_wall="$1"
    subsystem="$2"
    current_state="$3"
    requested_state="$4"
    source_ref="$5"
    context="$6"

    printf '%s | %s current=%s requested=%s source=%s context=%s' \
        "$ts_wall" "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

# ---------------------------------------------------------------------------
# FSM — per-subsystem state machine checks
# ---------------------------------------------------------------------------

# Return the path of the persisted last-state file for a subsystem.
trace_fsm_state_file() {
    printf '%s/%s.state\n' "$TRACE_FSM_DIR" "$1"
}

# Read the last known resulting state for a subsystem (empty string if unknown).
trace_fsm_get_last_state() {
    _fsm_file="$(trace_fsm_state_file "$1")"
    if [ -r "$_fsm_file" ]; then
        cat "$_fsm_file" 2>/dev/null
    fi
}

# Persist the new resulting state for a subsystem.
trace_fsm_set_last_state() {
    _fsm_file="$(trace_fsm_state_file "$1")"
    mkdir -p "$TRACE_FSM_DIR" 2>/dev/null
    printf '%s\n' "$2" > "$_fsm_file"
}

# Return 0 if from_state → to_state is a valid transition for subsystem.
# UNKNOWN on either side of the arrow is always accepted (insufficient info).
trace_fsm_valid_transition() {
    _fsm_sub="$1"
    _fsm_from="$2"
    _fsm_to="$3"

    # Can't validate if either side is unknown / empty
    case "$_fsm_from" in ''|UNKNOWN) return 0 ;; esac
    case "$_fsm_to"   in ''|UNKNOWN) return 0 ;; esac

    case "$_fsm_sub" in
        power)
            case "$_fsm_from" in
                BOOTING)
                    case "$_fsm_to" in RUNNING) return 0 ;; esac ;;
                RUNNING)
                    case "$_fsm_to" in SLEEP|OFF|REBOOT|LOW_BATTERY) return 0 ;; esac ;;
                SLEEP)
                    case "$_fsm_to" in RUNNING|OFF) return 0 ;; esac ;;
                LOW_BATTERY)
                    case "$_fsm_to" in RUNNING|OFF) return 0 ;; esac ;;
                OFF|REBOOT)
                    # terminal — nothing valid onward
                    return 1 ;;
                *)
                    # unrecognised state: allow to avoid false positives
                    return 0 ;;
            esac
            return 1
            ;;
        networking)
            case "$_fsm_from" in
                DISABLED)
                    case "$_fsm_to" in ENABLED) return 0 ;; esac ;;
                ENABLED)
                    case "$_fsm_to" in DISABLED|CONNECTED) return 0 ;; esac ;;
                CONNECTED)
                    case "$_fsm_to" in DISABLED|ENABLED) return 0 ;; esac ;;
                *)
                    return 0 ;;
            esac
            return 1
            ;;
        audio)
            # Any VOL_N → VOL_M transition is valid
            case "$_fsm_to" in VOL_*) return 0 ;; esac
            return 1
            ;;
        brightness)
            # Any BL_N → BL_M transition is valid
            case "$_fsm_to" in BL_*) return 0 ;; esac
            return 1
            ;;
        *)
            # Unknown subsystem — don't flag it
            return 0
            ;;
    esac
}

# Emit a dedicated inconsistency event into the same subsystem files.
# This is fire-and-forget; errors are suppressed so callers are never blocked.
trace_fsm_emit_inconsistency() {
    _incon_sub="$1"
    _incon_reason="$2"
    _incon_claimed_current="$3"
    _incon_requested="$4"
    _incon_source="$5"
    _incon_orig_context="$6"

    _incon_seq="$(trace_next_seq)"
    _incon_ts_mono="$(trace_monotonic_ts)"
    _incon_ts_wall="$(trace_wall_ts)"
    _incon_boot="$(trace_boot_id)"
    _incon_plat="${PLATFORM:-unknown}"
    _incon_build="$(trace_build)"

    _incon_context="FSM_INCONSISTENCY reason=${_incon_reason} claimed_current=${_incon_claimed_current} requested=${_incon_requested} orig_source=${_incon_source} orig_context=${_incon_orig_context}"

    _incon_json="$(trace_build_json_line \
        "$_incon_seq" "$_incon_sub" "INCONSISTENT" "INCONSISTENT" \
        "trace_fsm" \
        "$(trace_escape_json "$_incon_context")" \
        "$_incon_ts_mono" "$_incon_ts_wall" \
        "$_incon_boot" "$_incon_plat" "$_incon_build")"

    _incon_summary="$(trace_build_summary_line \
        "$_incon_ts_wall" "$_incon_sub" "INCONSISTENT" "INCONSISTENT" \
        "trace_fsm" "$_incon_context")"

    trace_emit_core \
        "$TRACE_EVENTS_FILE" "$TRACE_SUMMARY_FILE" \
        "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" \
        "$_incon_json" "$_incon_summary" 2>/dev/null || true
    trace_emit_core \
        "$(trace_subsystem_events_file "$_incon_sub")" \
        "$(trace_subsystem_summary_file "$_incon_sub")" \
        "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" \
        "$_incon_json" "$_incon_summary" 2>/dev/null || true
}

# Run both FSM checks and emit an inconsistency event if either fails.
# Never returns non-zero — the caller's execution must not be affected.
trace_fsm_check() {
    _fsmck_sub="$1"
    _fsmck_current="$2"
    _fsmck_requested="$3"
    _fsmck_source="$4"
    _fsmck_context="$5"

    # Check 1: continuity — does claimed current_state match last recorded state?
    _fsmck_last="$(trace_fsm_get_last_state "$_fsmck_sub")"
    if [ -n "$_fsmck_last" ] && \
       [ "$_fsmck_last" != "UNKNOWN" ] && \
       [ "$_fsmck_current" != "UNKNOWN" ] && \
       [ "$_fsmck_current" != "$_fsmck_last" ]; then
        trace_fsm_emit_inconsistency \
            "$_fsmck_sub" \
            "continuity:expected=${_fsmck_last}" \
            "$_fsmck_current" "$_fsmck_requested" \
            "$_fsmck_source" "$_fsmck_context" || true
    fi

    # Check 2: validity — is current_state → requested_state in the allowed set?
    if ! trace_fsm_valid_transition "$_fsmck_sub" "$_fsmck_current" "$_fsmck_requested"; then
        trace_fsm_emit_inconsistency \
            "$_fsmck_sub" \
            "invalid_transition:${_fsmck_current}->${_fsmck_requested}" \
            "$_fsmck_current" "$_fsmck_requested" \
            "$_fsmck_source" "$_fsmck_context" || true
    fi

    # Check 3: large ordinal jump (audio and brightness only)
    case "$_fsmck_sub" in
        audio)
            trace_fsm_check_level_jump \
                "$_fsmck_sub" "$_fsmck_current" "$_fsmck_requested" \
                "$_fsmck_source" "$_fsmck_context" \
                "$AUDIO_LARGE_JUMP_THRESHOLD" || true
            ;;
        brightness)
            trace_fsm_check_level_jump \
                "$_fsmck_sub" "$_fsmck_current" "$_fsmck_requested" \
                "$_fsmck_source" "$_fsmck_context" \
                "$BRIGHTNESS_LARGE_JUMP_THRESHOLD" || true
            ;;
    esac

    return 0
}

# Emit a lifecycle marker (boot/shutdown boundary) to the main trace files
# and to a dedicated lifecycle log for easy session-boundary reconstruction.
# Never returns non-zero.
trace_fsm_emit_lifecycle() {
    _lc_event="$1"    # e.g. FSM_INIT, FSM_FINALIZE, INCONSISTENT_START, INCONSISTENT_END
    _lc_context="$2"
    _lc_sub="${3:-power}"

    _lc_seq="$(trace_next_seq)"
    _lc_ts_mono="$(trace_monotonic_ts)"
    _lc_ts_wall="$(trace_wall_ts)"
    _lc_boot="$(trace_boot_id)"
    _lc_plat="${PLATFORM:-unknown}"
    _lc_build="$(trace_build)"

    _lc_json="$(trace_build_json_line \
        "$_lc_seq" "$_lc_sub" "$_lc_event" "$_lc_event" \
        "trace_fsm" \
        "$(trace_escape_json "$_lc_context")" \
        "$_lc_ts_mono" "$_lc_ts_wall" \
        "$_lc_boot" "$_lc_plat" "$_lc_build")"
    _lc_summary="$(trace_build_summary_line \
        "$_lc_ts_wall" "$_lc_sub" "$_lc_event" "$_lc_event" \
        "trace_fsm" "$_lc_context")"

    trace_ensure_dirs
    mkdir -p "$TRACE_FSM_DIR" 2>/dev/null

    trace_emit_core \
        "$TRACE_EVENTS_FILE" "$TRACE_SUMMARY_FILE" \
        "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" \
        "$_lc_json" "$_lc_summary" 2>/dev/null || true
    trace_emit_core \
        "$(trace_subsystem_events_file "$_lc_sub")" \
        "$(trace_subsystem_summary_file "$_lc_sub")" \
        "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" \
        "$_lc_json" "$_lc_summary" 2>/dev/null || true
    # dedicated lifecycle file — one line per session boundary, kept small
    printf '%s\n' "$_lc_summary" >> "$TRACE_FSM_DIR/lifecycle.txt" 2>/dev/null || true
}

# Called once during system startup (runtime.sh).
# 1. Inspects the persisted power state from the previous session:
#    - If it is not OFF/REBOOT/empty, the previous session ended uncleanly;
#      emit INCONSISTENT_END to record that.
# 2. Clears all FSM state files so the new session starts fresh.
# 3. Seeds power state as BOOTING and emits BOOTING→RUNNING + FSM_INIT.
# Never returns non-zero.
trace_fsm_boot_init() {
    _bi_source="${1:-runtime.sh}"

    trace_ensure_dirs
    mkdir -p "$TRACE_FSM_DIR" 2>/dev/null

    # -----------------------------------------------------------------------
    # TRACE_INITIALIZE — fires once, on the very first boot or after a full
    # trace wipe.  Detected by the absence of both:
    #   1. any persisted FSM state file (no prior session), AND
    #   2. any existing trace events file (no prior events at all).
    # Emitted to all subsystems before any other lifecycle event so it
    # appears as the first entry in every subsystem's trace log.
    # -----------------------------------------------------------------------
    _bi_any_state="$(ls "$TRACE_FSM_DIR"/*.state 2>/dev/null | head -n1)"
    if [ -z "$_bi_any_state" ] && [ ! -s "$TRACE_EVENTS_FILE" ]; then
        for _bi_init_sub in power networking audio brightness; do
            trace_fsm_emit_lifecycle \
                "TRACE_INITIALIZE" \
                "first trace session source=${_bi_source}" \
                "$_bi_init_sub" || true
        done
    fi

    # -----------------------------------------------------------------------
    # Check previous session end-state for each subsystem that has a defined
    # terminal state, before wiping the state files.
    # -----------------------------------------------------------------------

    # power: must have ended in OFF or REBOOT
    _bi_prev_power="$(trace_fsm_get_last_state power)"
    case "${_bi_prev_power:-}" in
        ''|OFF|REBOOT)
            ;; # clean end or first-ever boot
        *)
            trace_fsm_emit_lifecycle \
                "INCONSISTENT_END" \
                "previous session ended without OFF/REBOOT; last_state=${_bi_prev_power}" \
                "power" || true
            ;;
    esac

    # networking: must have ended in DISABLED (WiFi torn down during shutdown)
    _bi_prev_net="$(trace_fsm_get_last_state networking)"
    case "${_bi_prev_net:-}" in
        ''|DISABLED)
            ;; # expected or first-ever boot
        *)
            trace_fsm_emit_lifecycle \
                "INCONSISTENT_END" \
                "previous session ended without DISABLED; last_state=${_bi_prev_net}" \
                "networking" || true
            ;;
    esac

    # audio: no required terminal state — emit INCONSISTENT_START if last
    # recorded state is entirely absent after a non-first boot (power was
    # previously recorded, i.e. this isn't the very first ever run).
    # For audio and brightness we only flag a gap, not a wrong terminal state.
    _bi_prev_audio="$(trace_fsm_get_last_state audio)"
    if [ -n "${_bi_prev_power:-}" ] && [ -z "${_bi_prev_audio:-}" ]; then
        trace_fsm_emit_lifecycle \
            "INCONSISTENT_START" \
            "no audio state persisted from previous session" \
            "audio" || true
    fi

    _bi_prev_brightness="$(trace_fsm_get_last_state brightness)"
    if [ -n "${_bi_prev_power:-}" ] && [ -z "${_bi_prev_brightness:-}" ]; then
        trace_fsm_emit_lifecycle \
            "INCONSISTENT_START" \
            "no brightness state persisted from previous session" \
            "brightness" || true
    fi

    # -----------------------------------------------------------------------
    # Reset all subsystem state files — fresh session
    # -----------------------------------------------------------------------
    rm -f "$TRACE_FSM_DIR"/*.state 2>/dev/null || true

    # -----------------------------------------------------------------------
    # Seed power FSM: BOOTING → RUNNING (runs through normal FSM path)
    # -----------------------------------------------------------------------
    trace_fsm_set_last_state "power" "BOOTING" || true
    trace_write_system_emit "power" "BOOTING" "RUNNING" "$_bi_source" "system startup" || true

    # -----------------------------------------------------------------------
    # Emit FSM_INIT lifecycle marker for every subsystem
    # -----------------------------------------------------------------------
    for _bi_sub in power networking audio brightness; do
        trace_fsm_emit_lifecycle \
            "FSM_INIT" \
            "boot session started source=${_bi_source}" \
            "$_bi_sub" || true
    done

    return 0
}

# Called once during shutdown (save_poweroff.sh), after the power-state emit
# and before stage 2 takes over.
# 1. Validates that the power FSM is now in OFF or REBOOT (i.e. the emit
#    actually happened).  If not, records INCONSISTENT_END.
# 2. Writes FSM_FINALIZE to close the session cleanly.
# Never returns non-zero.
trace_fsm_shutdown_finalize() {
    _sf_source="${1:-save_poweroff.sh}"

    # -----------------------------------------------------------------------
    # Validate terminal states for subsystems that require them
    # -----------------------------------------------------------------------

    # power: must be OFF or REBOOT
    _sf_power="$(trace_fsm_get_last_state power)"
    case "${_sf_power:-}" in
        OFF|REBOOT)
            ;; # expected
        *)
            trace_fsm_emit_lifecycle \
                "INCONSISTENT_END" \
                "shutdown finalised without OFF/REBOOT; last_state=${_sf_power}" \
                "power" || true
            ;;
    esac

    # networking: must be DISABLED (torn down before unmount)
    _sf_net="$(trace_fsm_get_last_state networking)"
    case "${_sf_net:-}" in
        ''|DISABLED)
            ;; # expected or never emitted
        *)
            trace_fsm_emit_lifecycle \
                "INCONSISTENT_END" \
                "shutdown finalised without DISABLED; last_state=${_sf_net}" \
                "networking" || true
            ;;
    esac

    # audio: no required terminal state — absence of any recorded state
    # after a session that did reach RUNNING is worth flagging
    _sf_audio="$(trace_fsm_get_last_state audio)"
    if [ "${_sf_power:-}" = "OFF" ] || [ "${_sf_power:-}" = "REBOOT" ]; then
        if [ -z "${_sf_audio:-}" ]; then
            trace_fsm_emit_lifecycle \
                "INCONSISTENT_END" \
                "no audio state recorded this session" \
                "audio" || true
        fi

        _sf_brightness="$(trace_fsm_get_last_state brightness)"
        if [ -z "${_sf_brightness:-}" ]; then
            trace_fsm_emit_lifecycle \
                "INCONSISTENT_END" \
                "no brightness state recorded this session" \
                "brightness" || true
        fi
    fi

    # -----------------------------------------------------------------------
    # FSM_FINALIZE lifecycle marker for every subsystem
    # -----------------------------------------------------------------------
    for _sf_sub in power networking audio brightness; do
        trace_fsm_emit_lifecycle \
            "FSM_FINALIZE" \
            "shutdown sequence completed source=${_sf_source}" \
            "$_sf_sub" || true
    done

    return 0
}

# Extract the trailing integer from a state name such as VOL_12 or BL_3.
# Prints the number, or nothing if the state has no numeric suffix.
trace_fsm_extract_level() {
    printf '%s\n' "$1" | sed 's/^[^_]*_//; /^[0-9][0-9]*$/!d'
}

# Check whether the transition from->to represents a large jump for ordinal
# subsystems (audio, brightness).  Emits an inconsistency event if the
# absolute delta exceeds the configured threshold.  Never returns non-zero.
trace_fsm_check_level_jump() {
    _lj_sub="$1"
    _lj_from="$2"
    _lj_to="$3"
    _lj_source="$4"
    _lj_context="$5"
    _lj_threshold="$6"

    # Threshold of 0 means the check is disabled
    case "${_lj_threshold:-0}" in
        ''|0|*[!0-9]*) return 0 ;;
    esac

    _lj_from_n="$(trace_fsm_extract_level "$_lj_from")"
    _lj_to_n="$(trace_fsm_extract_level "$_lj_to")"

    # Only meaningful when both states carry a numeric level
    [ -n "$_lj_from_n" ] && [ -n "$_lj_to_n" ] || return 0

    _lj_delta=$(( _lj_to_n - _lj_from_n ))
    [ "$_lj_delta" -lt 0 ] && _lj_delta=$(( -_lj_delta ))

    if [ "$_lj_delta" -gt "$_lj_threshold" ]; then
        trace_fsm_emit_inconsistency \
            "$_lj_sub" \
            "large_jump:delta=${_lj_delta},threshold=${_lj_threshold},from=${_lj_from},to=${_lj_to}" \
            "$_lj_from" "$_lj_to" \
            "$_lj_source" "$_lj_context" || true
    fi

    return 0
}

# ---------------------------------------------------------------------------

trace_write_system_emit() {
    subsystem="$(trace_normalize_subsystem "$1")"
    current_state="${2:-UNKNOWN}"
    requested_state="${3:-$current_state}"
    source_ref="${4:-unknown}"
    context="${5:-}"

    [ -n "$current_state" ] || current_state="UNKNOWN"
    [ -n "$requested_state" ] || requested_state="$current_state"
    [ -n "$source_ref" ] || source_ref="unknown"

    trace_gate_enabled "$subsystem" || return 0

    # FSM check: run before the normal emit so any inconsistency event gets a
    # lower sequence number and appears just before the transition in the log.
    trace_fsm_check "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context" || true

    trace_next_seq >/dev/null
    seq="$trace_seq"
    ts_mono="$(trace_monotonic_ts)"
    ts_wall="$(trace_wall_ts)"
    boot_session_id="$(trace_boot_id)"
    platform_id="${PLATFORM:-unknown}"
    build_id="$(trace_build)"

    json_line="$(trace_build_json_line "$seq" "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context" "$ts_mono" "$ts_wall" "$boot_session_id" "$platform_id" "$build_id")"
    summary_line="$(trace_build_summary_line "$ts_wall" "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context")"

    trace_emit_core "$TRACE_EVENTS_FILE" "$TRACE_SUMMARY_FILE" "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" "$json_line" "$summary_line"
    trace_emit_core "$(trace_subsystem_events_file "$subsystem")" "$(trace_subsystem_summary_file "$subsystem")" "$TRACE_MAX_EVENTS" "$TRACE_MAX_SUMMARY_LINES" "$json_line" "$summary_line"

    # Persist the new state so the next emit can check continuity.
    trace_fsm_set_last_state "$subsystem" "$requested_state" || true
    trace_cache_write_state "$subsystem" "$requested_state" || true
}

system_emit() {
    [ "$#" -ge 4 ] || return 1

    subsystem="$(trace_normalize_subsystem "$1")"
    current_state="${2:-UNKNOWN}"
    requested_state="${3:-$current_state}"
    source_ref="${4:-unknown}"
    shift 4
    context="$*"

    trace_write_system_emit "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

trace_format_level_state() {
    prefix="$1"
    raw_value="$2"
    fallback="${3:-UNKNOWN}"

    case "$raw_value" in
        ''|UNKNOWN|AUTO)
            printf '%s\n' "$fallback"
            ;;
        "${prefix}"_*)
            printf '%s\n' "$raw_value"
            ;;
        *[!0-9]*)
            printf '%s\n' "$fallback"
            ;;
        *)
            printf '%s_%s\n' "$prefix" "$raw_value"
            ;;
    esac
}

trace_is_uint() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

trace_emit_cached_or_unknown() {
    [ "$#" -ge 3 ] || return 1

    subsystem="$(trace_normalize_subsystem "$1")"
    source_ref="$2"
    shift 2
    context="$*"

    cached_state="$(trace_cache_read_state "$subsystem")"
    case "$cached_state" in
        '')
            current_state="UNKNOWN"
            requested_state="UNKNOWN"
            ;;
        *)
            current_state="$cached_state"
            requested_state="$cached_state"
            ;;
    esac

    system_emit "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

trace_emit_from_current_to_cached_or_unknown() {
    [ "$#" -ge 4 ] || return 1

    subsystem="$(trace_normalize_subsystem "$1")"
    current_state="${2:-UNKNOWN}"
    source_ref="$3"
    shift 3
    context="$*"

    cached_state="$(trace_cache_read_state "$subsystem")"
    case "$cached_state" in
        '')
            requested_state="UNKNOWN"
            ;;
        *)
            requested_state="$cached_state"
            ;;
    esac

    system_emit "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}

power_trace_emit() {
    if [ "$#" -eq 4 ]; then
        system_emit "power" "$1" "$2" "$3" "$4"
        return
    fi

    event="$1"
    prev_state="${2:-UNKNOWN}"
    intended_state="${3:-$prev_state}"
    observed_state="${4:-$prev_state}"
    source_ref="${6:-power_trace_emit}"
    shift 6 2>/dev/null || true

    case "$observed_state" in
        ''|AUTO) current_state="$prev_state" ;;
        *) current_state="$observed_state" ;;
    esac
    case "$current_state" in
        ''|AUTO) current_state="UNKNOWN" ;;
    esac
    case "$intended_state" in
        ''|AUTO) requested_state="$current_state" ;;
        *) requested_state="$intended_state" ;;
    esac

    context="$event"
    for extra in "$@"; do
        [ -n "$extra" ] || continue
        context="$context $extra"
    done

    system_emit "power" "$current_state" "$requested_state" "$source_ref" "$context"
}

power_trace_emit_shutdown_request() {
    shutdown_mode="${1:-}"
    source_ref="${2:-save_poweroff.sh}"
    shift 2
    context="$*"

    case "$shutdown_mode" in
        --reboot|REBOOT|reboot)
            requested_state="REBOOT"
            ;;
        *)
            requested_state="OFF"
            ;;
    esac

    current_state="$(trace_fsm_get_last_state "power" 2>/dev/null)"
    case "${current_state:-}" in
        RUNNING|SLEEP|LOW_BATTERY) ;;
        *) current_state="RUNNING" ;;
    esac

    system_emit "power" "$current_state" "$requested_state" "$source_ref" "$context"
}

audio_trace_emit() {
    [ "$#" -eq 4 ] || return 1
    system_emit "audio" "$1" "$2" "$3" "$4"
}

audio_trace_emit_level() {
    [ "$#" -ge 2 ] || return 1

    requested_state="$(trace_format_level_state "VOL" "$1" "UNKNOWN")"
    source_ref="$2"
    shift 2
    context="$*"

    audio_trace_emit "UNKNOWN" "$requested_state" "$source_ref" "$context"
}

audio_trace_emit_levels() {
    [ "$#" -ge 3 ] || return 1

    current_state="$(trace_format_level_state "VOL" "$1" "UNKNOWN")"
    requested_state="$(trace_format_level_state "VOL" "$2" "$current_state")"
    source_ref="$3"
    shift 3
    context="$*"

    audio_trace_emit "$current_state" "$requested_state" "$source_ref" "$context"
}

audio_trace_emit_cached_or_unknown() {
    [ "$#" -ge 1 ] || return 1

    source_ref="$1"
    shift
    context="$*"
    trace_emit_cached_or_unknown "audio" "$source_ref" "$context"
}

audio_trace_emit_from_current_to_cached_or_unknown() {
    [ "$#" -ge 2 ] || return 1

    current_state="$(trace_format_level_state "VOL" "$1" "UNKNOWN")"
    source_ref="$2"
    shift 2
    context="$*"
    trace_emit_from_current_to_cached_or_unknown "audio" "$current_state" "$source_ref" "$context"
}

audio_trace_emit_startup_baseline_if_missing() {
    source_ref="${1:-runtimeHelper.sh}"
    shift
    context="$*"
    [ -n "$context" ] || context="startup volume baseline cached or unavailable"

    startup_audio_last="$(trace_fsm_get_last_state "audio" 2>/dev/null)"
    [ -n "$startup_audio_last" ] || audio_trace_emit_cached_or_unknown "$source_ref" "$context"
}

audio_trace_emit_shutdown_baseline_if_missing() {
    source_ref="${1:-save_poweroff.sh}"
    shift
    context="$*"
    [ -n "$context" ] || context="shutdown fallback volume baseline cached or unavailable"

    shutdown_audio_last="$(trace_fsm_get_last_state "audio" 2>/dev/null)"
    [ -n "$shutdown_audio_last" ] || audio_trace_emit_cached_or_unknown "$source_ref" "$context"
}

audio_trace_emit_wake_restore() {
    [ "$#" -ge 3 ] || return 1

    current_raw="$1"
    restore_raw="$2"
    source_ref="$3"
    shift 3
    context="$*"

    current_state="$(trace_format_level_state "VOL" "$current_raw" "UNKNOWN")"
    if trace_is_uint "$restore_raw"; then
        restore_context="$context"
        [ -n "$restore_context" ] || restore_context="volume restored on wake"
        requested_state="$(trace_format_level_state "VOL" "$restore_raw" "$current_state")"
        audio_trace_emit "$current_state" "$requested_state" "$source_ref" "$restore_context"
    else
        fallback_context="$context"
        [ -n "$fallback_context" ] || fallback_context="volume restore cached or unavailable on wake"
        trace_emit_from_current_to_cached_or_unknown "audio" "$current_state" "$source_ref" "$fallback_context"
    fi
}

network_trace_emit() {
    [ "$#" -eq 4 ] || return 1
    system_emit "networking" "$1" "$2" "$3" "$4"
}

brightness_trace_emit() {
    [ "$#" -eq 4 ] || return 1
    system_emit "brightness" "$1" "$2" "$3" "$4"
}

brightness_trace_emit_level() {
    [ "$#" -ge 2 ] || return 1

    requested_state="$(trace_format_level_state "BL" "$1" "UNKNOWN")"
    source_ref="$2"
    shift 2
    context="$*"

    brightness_trace_emit "UNKNOWN" "$requested_state" "$source_ref" "$context"
}

brightness_trace_emit_levels() {
    [ "$#" -ge 3 ] || return 1

    current_state="$(trace_format_level_state "BL" "$1" "UNKNOWN")"
    requested_state="$(trace_format_level_state "BL" "$2" "$current_state")"
    source_ref="$3"
    shift 3
    context="$*"

    brightness_trace_emit "$current_state" "$requested_state" "$source_ref" "$context"
}

brightness_trace_emit_cached_or_unknown() {
    [ "$#" -ge 1 ] || return 1

    source_ref="$1"
    shift
    context="$*"
    trace_emit_cached_or_unknown "brightness" "$source_ref" "$context"
}

brightness_trace_emit_from_current_to_cached_or_unknown() {
    [ "$#" -ge 2 ] || return 1

    current_state="$(trace_format_level_state "BL" "$1" "UNKNOWN")"
    source_ref="$2"
    shift 2
    context="$*"
    trace_emit_from_current_to_cached_or_unknown "brightness" "$current_state" "$source_ref" "$context"
}

brightness_trace_emit_startup_baseline_if_missing() {
    source_ref="${1:-runtimeHelper.sh}"
    shift
    context="$*"
    [ -n "$context" ] || context="startup brightness baseline cached or unavailable"

    startup_bl_last="$(trace_fsm_get_last_state "brightness" 2>/dev/null)"
    [ -n "$startup_bl_last" ] || brightness_trace_emit_cached_or_unknown "$source_ref" "$context"
}

brightness_trace_emit_shutdown_baseline_if_missing() {
    source_ref="${1:-save_poweroff.sh}"
    shift
    context="$*"
    [ -n "$context" ] || context="shutdown fallback brightness baseline cached or unavailable"

    shutdown_bl_last="$(trace_fsm_get_last_state "brightness" 2>/dev/null)"
    [ -n "$shutdown_bl_last" ] || brightness_trace_emit_cached_or_unknown "$source_ref" "$context"
}

brightness_trace_emit_wake_baseline() {
    [ "$#" -ge 2 ] || return 1

    wake_raw="$1"
    source_ref="$2"
    shift 2
    context="$*"

    if trace_is_uint "$wake_raw"; then
        wake_context="$context"
        [ -n "$wake_context" ] || wake_context="brightness baseline on wake"
        wake_state="$(trace_format_level_state "BL" "$wake_raw" "UNKNOWN")"
        brightness_trace_emit "$wake_state" "$wake_state" "$source_ref" "$wake_context"
    else
        fallback_context="$context"
        [ -n "$fallback_context" ] || fallback_context="brightness baseline cached or unavailable on wake"
        brightness_trace_emit_cached_or_unknown "$source_ref" "$fallback_context"
    fi
}

av_trace_emit_startup_baselines_if_missing() {
    source_ref="${1:-runtimeHelper.sh}"
    audio_trace_emit_startup_baseline_if_missing "$source_ref" || true
    brightness_trace_emit_startup_baseline_if_missing "$source_ref" || true
}

av_trace_emit_shutdown_baselines_if_missing() {
    source_ref="${1:-save_poweroff.sh}"
    audio_trace_emit_shutdown_baseline_if_missing "$source_ref" || true
    brightness_trace_emit_shutdown_baseline_if_missing "$source_ref" || true
}

trace_process_lane_id() {
    lane="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"
    case "$lane" in
        ''|-) lane="unknown" ;;
        archiveunpacker) lane="archiveunpacker" ;;
        firstboot) lane="firstboot" ;;
    esac
    printf '%s\n' "$lane"
}

process_trace_subsystem() {
    lane_id="$(trace_process_lane_id "$1")"
    printf '%s\n' "process-${lane_id}"
}

process_trace_init() {
    [ "$#" -ge 2 ] || return 1

    lane_id="$(trace_process_lane_id "$1")"
    source_ref="${2:-unknown}"
    shift 2
    context="$*"

    subsystem="$(process_trace_subsystem "$lane_id")"
    last_state="$(trace_fsm_get_last_state "$subsystem")"
    [ -n "$last_state" ] || last_state="UNKNOWN"

    case "$last_state" in
        UNKNOWN|FINALIZED|COMPLETE|FAILED|HANDOFF_BACKGROUND|SKIPPED_LOCK)
            ;;
        *)
            trace_fsm_emit_inconsistency \
                "$subsystem" \
                "init_without_finalize:last_state=${last_state}" \
                "$last_state" "RUNNING" \
                "$source_ref" "$context" || true
            ;;
    esac

    system_emit "$subsystem" "$last_state" "RUNNING" "$source_ref" "FSM_INIT lane=${lane_id} ${context}"
}

process_trace_finalize() {
    [ "$#" -ge 2 ] || return 1

    lane_id="$(trace_process_lane_id "$1")"
    source_ref="${2:-unknown}"
    if [ "$#" -ge 3 ]; then
        final_state="${3:-FINALIZED}"
        shift 3
    else
        final_state="FINALIZED"
        shift 2
    fi
    context="$*"

    subsystem="$(process_trace_subsystem "$lane_id")"
    current_state="$(trace_fsm_get_last_state "$subsystem")"
    [ -n "$current_state" ] || current_state="UNKNOWN"

    case "$final_state" in
        ''|AUTO)
            final_state="FINALIZED"
            ;;
    esac

    if [ "$current_state" = "UNKNOWN" ]; then
        trace_fsm_emit_inconsistency \
            "$subsystem" \
            "finalize_without_init" \
            "$current_state" "$final_state" \
            "$source_ref" "$context" || true
    fi

    system_emit "$subsystem" "$current_state" "$final_state" "$source_ref" "FSM_FINALIZE lane=${lane_id} ${context}"
}

process_trace_emit() {
    [ "$#" -ge 3 ] || return 1

    lane_id="$(trace_process_lane_id "$1")"
    requested_state="${2:-UNKNOWN}"
    source_ref="${3:-unknown}"
    shift 3
    context="$*"

    subsystem="$(process_trace_subsystem "$lane_id")"
    current_state="$(trace_cache_read_state "$subsystem")"
    [ -n "$current_state" ] || current_state="UNKNOWN"

    case "$requested_state" in
        ''|AUTO) requested_state="$current_state" ;;
    esac

    system_emit "$subsystem" "$current_state" "$requested_state" "$source_ref" "$context"
}
