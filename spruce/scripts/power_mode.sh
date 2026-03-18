#!/bin/sh

# Canonical power lifecycle runtime state contract.
# IMPORTANT: POWER_MODE_STATE_FILE is private to this module and must only be
# read/written via power_mode_* helpers. Callers must never mutate it directly.
: "${POWER_MODE_STATE_FILE:=/tmp/power_mode.state}"
: "${POWER_MODE_LOCK_DIR:=/tmp/power_mode.lockdir}"
: "${POWER_MODE_LOCK_RETRIES:=50}"
: "${POWER_MODE_LOCK_SLEEP_SEC:=0.02}"

power_mode__default_mode="running"
power_mode__default_owner="watchdog"
power_mode__default_shutdown_pending="0"
power_mode__default_rearm_until="0"
power_mode__default_generation="0"

power_mode__log() {
    msg="$1"
    if command -v log_message >/dev/null 2>&1; then
        log_message "power_mode.sh: ${msg}" -v
    fi
}

power_mode__set_defaults() {
    power_mode="$power_mode__default_mode"
    power_owner="$power_mode__default_owner"
    power_shutdown_pending="$power_mode__default_shutdown_pending"
    power_rearm_until="$power_mode__default_rearm_until"
    power_generation="$power_mode__default_generation"
}


power_mode__set_failsafe_fence() {
    # Corrupt/invalid state must fail closed so runtime callers do not
    # accidentally bypass a real shutdown fence.
    power_mode="shutdown_pending"
    power_owner="corrupt_state"
    power_shutdown_pending="1"
    power_rearm_until="0"
    power_generation="$power_mode__default_generation"
}

power_mode__is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

power_mode__is_valid_mode() {
    case "$1" in
        running|sleep_owned|waking|shutdown_pending) return 0 ;;
        *) return 1 ;;
    esac
}

power_mode__is_valid_owner() {
    case "$1" in
        ''|*[!A-Za-z0-9_.-]*) return 1 ;;
        *) return 0 ;;
    esac
}

power_mode__strip_quoted_value() {
    raw="$1"

    case "$raw" in
        '"'*) ;;
        *) return 1 ;;
    esac

    val="${raw#\"}"
    case "$val" in
        *'"') val="${val%\"}" ;;
        *) return 1 ;;
    esac

    printf '%s\n' "$val"
}

power_mode__load_unlocked() {
    power_mode__set_defaults
    power_mode_load_valid=1

    [ -f "$POWER_MODE_STATE_FILE" ] || return 0

    found_mode=0
    found_owner=0
    found_pending=0
    found_rearm=0
    found_generation=0

    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue

        key="${line%%=*}"
        if [ "$key" = "$line" ]; then
            power_mode_load_valid=0
            power_mode__log "state parse error: malformed line without key/value separator"
            continue
        fi

        raw_value="${line#*=}"
        if ! value="$(power_mode__strip_quoted_value "$raw_value")"; then
            power_mode_load_valid=0
            power_mode__log "state parse error: key ${key} is not quoted properly"
            continue
        fi

        case "$key" in
            power_mode)
                if power_mode__is_valid_mode "$value"; then
                    power_mode="$value"
                    found_mode=1
                else
                    power_mode_load_valid=0
                    power_mode__log "state parse error: invalid power_mode value ${value}"
                fi
                ;;
            power_owner)
                if power_mode__is_valid_owner "$value"; then
                    power_owner="$value"
                    found_owner=1
                else
                    power_mode_load_valid=0
                    power_mode__log "state parse error: invalid power_owner value ${value}"
                fi
                ;;
            power_shutdown_pending)
                if [ "$value" = "0" ] || [ "$value" = "1" ]; then
                    power_shutdown_pending="$value"
                    found_pending=1
                else
                    power_mode_load_valid=0
                    power_mode__log "state parse error: invalid power_shutdown_pending value ${value}"
                fi
                ;;
            power_rearm_until)
                if power_mode__is_uint "$value"; then
                    power_rearm_until="$value"
                    found_rearm=1
                else
                    power_mode_load_valid=0
                    power_mode__log "state parse error: invalid power_rearm_until value ${value}"
                fi
                ;;
            power_generation)
                if power_mode__is_uint "$value"; then
                    power_generation="$value"
                    found_generation=1
                else
                    power_mode_load_valid=0
                    power_mode__log "state parse error: invalid power_generation value ${value}"
                fi
                ;;
            power_updated_at)
                # Observability field only; ignore for control-plane decisions.
                ;;
            *)
                power_mode_load_valid=0
                power_mode__log "state parse error: unknown key ${key}"
                ;;
        esac
    done < "$POWER_MODE_STATE_FILE"

    [ "$found_mode" -eq 1 ] || power_mode_load_valid=0
    [ "$found_owner" -eq 1 ] || power_mode_load_valid=0
    [ "$found_pending" -eq 1 ] || power_mode_load_valid=0
    [ "$found_rearm" -eq 1 ] || power_mode_load_valid=0
    [ "$found_generation" -eq 1 ] || power_mode_load_valid=0

    if [ "$power_mode_load_valid" -ne 1 ]; then
        power_mode__log "state load invalid; entering fail-safe shutdown fence in-memory"
        power_mode__set_failsafe_fence
    fi
}

power_mode__acquire_lock() {
    i=0
    while [ "$i" -lt "$POWER_MODE_LOCK_RETRIES" ]; do
        if mkdir "$POWER_MODE_LOCK_DIR" 2>/dev/null; then
            printf '%s\n' "$$" > "$POWER_MODE_LOCK_DIR/pid" 2>/dev/null || true
            return 0
        fi

        if [ -f "$POWER_MODE_LOCK_DIR/pid" ]; then
            lock_pid="$(cat "$POWER_MODE_LOCK_DIR/pid" 2>/dev/null)"
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$POWER_MODE_LOCK_DIR" 2>/dev/null || true
                continue
            fi
        fi

        sleep "$POWER_MODE_LOCK_SLEEP_SEC"
        i=$((i + 1))
    done

    power_mode__log "lock acquisition failed for ${POWER_MODE_LOCK_DIR}"
    return 1
}

power_mode__release_lock() {
    rm -rf "$POWER_MODE_LOCK_DIR" 2>/dev/null || true
}

power_mode_load() {
    power_mode__load_unlocked
}

power_mode_get() {
    power_mode_load
    printf '%s\n' "$power_mode"
}

power_mode_generation_get() {
    power_mode_load
    printf '%s\n' "$power_generation"
}

power_mode__is_transition_allowed() {
    old_mode="$1"
    new_mode="$2"

    case "$old_mode:$new_mode" in
        running:running|running:sleep_owned|running:shutdown_pending)
            return 0
            ;;
        sleep_owned:sleep_owned|sleep_owned:waking|sleep_owned:shutdown_pending)
            return 0
            ;;
        waking:waking|waking:running|waking:shutdown_pending)
            return 0
            ;;
        shutdown_pending:shutdown_pending)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

power_mode__write_state_locked() {
    mode="$1"
    owner="$2"
    shutdown_pending="$3"
    rearm_until="$4"
    allow_shutdown_clear="${5:-0}"

    power_mode__load_unlocked

    old_mode="$power_mode"
    old_owner="$power_owner"
    old_pending="$power_shutdown_pending"
    old_rearm="$power_rearm_until"
    old_generation="$power_generation"

    if [ "$old_pending" = "1" ] && [ "$shutdown_pending" != "1" ] && [ "$allow_shutdown_clear" != "1" ]; then
        power_mode__log "reject transition ${old_mode}/${old_owner}/pending=${old_pending} -> ${mode}/${owner}/pending=${shutdown_pending}: shutdown_pending is monotonic"
        return 1
    fi

    if [ "$allow_shutdown_clear" != "1" ] || [ "$mode" != "running" ]; then
        if ! power_mode__is_transition_allowed "$old_mode" "$mode"; then
            power_mode__log "reject invalid transition ${old_mode} -> ${mode}"
            return 1
        fi
    fi

    if ! power_mode__is_valid_mode "$mode"; then
        power_mode__log "reject transition with invalid destination mode ${mode}"
        return 1
    fi

    if ! power_mode__is_valid_owner "$owner"; then
        power_mode__log "reject transition with invalid owner=${owner}"
        return 1
    fi

    if [ "$shutdown_pending" != "0" ] && [ "$shutdown_pending" != "1" ]; then
        power_mode__log "reject transition with invalid shutdown_pending=${shutdown_pending}"
        return 1
    fi

    if ! power_mode__is_uint "$rearm_until"; then
        power_mode__log "reject transition with invalid rearm_until=${rearm_until}"
        return 1
    fi

    new_generation=$((old_generation + 1))
    tmp_file="${POWER_MODE_STATE_FILE}.$$.tmp"
    previous_umask="$(umask)"
    umask 077
    if ! {
        printf 'power_mode="%s"\n' "$mode"
        printf 'power_owner="%s"\n' "$owner"
        printf 'power_shutdown_pending="%s"\n' "$shutdown_pending"
        printf 'power_rearm_until="%s"\n' "$rearm_until"
        printf 'power_generation="%s"\n' "$new_generation"
        printf 'power_updated_at="%s"\n' "$(date +%s)"
    } > "$tmp_file"; then
        umask "$previous_umask"
        return 1
    fi
    umask "$previous_umask"

    if ! mv -f "$tmp_file" "$POWER_MODE_STATE_FILE"; then
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    fi

    power_mode__log "commit gen=${new_generation} ${old_mode}/${old_owner}/pending=${old_pending}/rearm=${old_rearm} -> ${mode}/${owner}/pending=${shutdown_pending}/rearm=${rearm_until}"
    return 0
}

power_mode__transition() {
    mode="$1"
    owner="$2"
    shutdown_pending="$3"
    rearm_until="$4"
    allow_shutdown_clear="${5:-0}"

    power_mode__acquire_lock || return 1
    if power_mode__write_state_locked "$mode" "$owner" "$shutdown_pending" "$rearm_until" "$allow_shutdown_clear"; then
        power_mode__release_lock
        return 0
    fi

    power_mode__release_lock
    return 1
}

power_mode_set_running() {
    owner="${1:-watchdog}"
    power_mode__transition "running" "$owner" "0" "0" "0"
}

power_mode_claim_sleep_owner() {
    owner="${1:-sleep_helper}"
    power_mode__transition "sleep_owned" "$owner" "0" "0" "0"
}

power_mode_enter_rearm() {
    owner="${1:-sleep_helper}"
    rearm_seconds="${2:-3}"

    if ! power_mode__is_uint "$rearm_seconds"; then
        power_mode__log "reject rearm request with invalid rearm_seconds=${rearm_seconds}"
        return 1
    fi

    now="$(date +%s)"
    rearm_until=$((now + rearm_seconds))

    power_mode__transition "waking" "$owner" "0" "$rearm_until" "0"
}

power_mode_mark_shutdown_pending() {
    owner="${1:-shutdown}"
    power_mode__transition "shutdown_pending" "$owner" "1" "0" "0"
}

power_mode_boot_reset_running() {
    owner="${1:-watchdog}"
    power_mode__transition "running" "$owner" "0" "0" "1"
}

power_mode_is_shutdown_pending() {
    power_mode_load
    [ "$power_shutdown_pending" = "1" ]
}

power_mode_may_accept_sleep_requests() {
    power_mode_load

    [ "$power_shutdown_pending" = "1" ] && return 1
    [ "$power_mode" = "running" ] || return 1
    [ "$power_owner" = "watchdog" ] || return 1
    return 0
}

power_mode_watchdog_reconcile_after_rearm() {
    power_mode_load

    [ "$power_shutdown_pending" = "1" ] && return 1
    [ "$power_mode" = "waking" ] || return 1

    now="$(date +%s)"
    if [ -n "$power_rearm_until" ] && [ "$now" -lt "$power_rearm_until" ] 2>/dev/null; then
        return 1
    fi

    power_mode_set_running "watchdog"
}

power_mode_watchdog_may_handle_input() {
    power_mode_load

    if [ "$power_shutdown_pending" = "1" ]; then
        return 1
    fi

    case "$power_mode" in
        sleep_owned)
            return 1
            ;;
        waking)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}
