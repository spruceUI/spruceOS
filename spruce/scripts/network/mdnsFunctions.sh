#!/bin/sh

# mDNS responder lifecycle. Callers must already have sourced helperFunctions.sh
# and hostnameFunctions.sh. Run contract: spruce/bin/mdns/README.md.

if [ "${PLATFORM_ARCHITECTURE:-}" = "armhf" ]; then
    MDNS_BIN="${MDNS_BIN:-/mnt/SDCARD/spruce/bin/mdns/mdnsd}"
else # aarch64
    MDNS_BIN="${MDNS_BIN:-/mnt/SDCARD/spruce/bin64/mdns/mdnsd}"
fi
MDNS_SERVICE_DIR="${MDNS_SERVICE_DIR:-/tmp/mdns}"
MDNS_PID_FILE="${MDNS_PID_FILE:-/tmp/mdnsd.pid}"
MDNS_START_LOCK="${MDNS_START_LOCK:-/tmp/mdnsd_starting}"
MDNS_PROC_DIR="${MDNS_PROC_DIR:-/proc}"

# Some firmware runs its own responder, avahi-daemon (the RGSP's publishes the kernel hostname).
AVAHI_BIN="${AVAHI_BIN:-/usr/sbin/avahi-daemon}"
AVAHI_FLAGS="${AVAHI_FLAGS:---daemonize --no-drop-root --no-proc-title}"
# The name avahi was last started with by spruce. Missing: it still has the firmware's boot name.
AVAHI_NAME_FILE="${AVAHI_NAME_FILE:-/tmp/spruce_avahi_hostname}"

# Only worth answering as <name>.local while something is listening to reach.
# networkservices.sh has already read the four settings; reuse them rather than run jq again.
mdns_services_wanted() {
    if [ -n "${samba_enabled:-}" ] && [ -n "${ssh_enabled:-}" ] &&
        [ -n "${sftpgo_enabled:-}" ] && [ -n "${syncthing_enabled:-}" ]; then
        case " $samba_enabled $ssh_enabled $sftpgo_enabled $syncthing_enabled " in
            *" True "*) return 0 ;;
        esac
        return 1
    fi
    for _key in enableSamba enableSSH enableSFTPGo enableSyncthing; do
        [ "$(get_config_value ".menuOptions.\"Network Settings\".$_key.selected" "False")" = "True" ] && return 0
    done
    return 1
}

# Pids of our mdnsd. By path: the firmware busybox "pgrep -x mdnsd" does not find it (RGSP).
# "pgrep -f <path>" alone is too loose - anything carrying the path further along its arguments
# matches, and stop kills what this prints - so keep only pids whose argv[0] is the binary.
mdns_pids() {
    for _pid in $(pgrep -f "$MDNS_BIN" 2>/dev/null); do
        [ "$(tr '\0' '\n' <"$MDNS_PROC_DIR/$_pid/cmdline" 2>/dev/null | head -n 1)" = "$MDNS_BIN" ] &&
            echo "$_pid"
    done
}

mdns_is_running() {
    [ -n "$(mdns_pids)" ]
}

# avahi's own check (as BaseOS's baseos-mdns does), so busybox pgrep plays no part.
avahi_is_running() {
    [ -x "$AVAHI_BIN" ] && "$AVAHI_BIN" --check >/dev/null 2>&1
}

# Wait up to 2 s for avahi to exit.
_avahi_wait_gone() {
    _waited=0
    while avahi_is_running && [ "$_waited" -lt 20 ]; do
        sleep 0.1
        _waited=$((_waited + 1))
    done
}

# avahi reads the kernel hostname only at start, so restart it when the name it announces is not
# the spruce one. It is the firmware's: never stopped for good, only restarted.
# $1: the spruce name, when the caller already has it.
announce_via_avahi() {
    _name="${1:-$(get_spruce_hostname)}"
    echo "$_name" >"$HOSTNAME_STATE_FILE"
    read -r _announced 2>/dev/null <"$AVAHI_NAME_FILE" || _announced=""
    [ "$_announced" = "$_name" ] && return 0

    log_message "Restarting avahi-daemon to announce $_name.local..."
    "$AVAHI_BIN" -k >/dev/null 2>&1
    # A start while the old one still runs fails, so wait for it to go.
    _avahi_wait_gone
    if avahi_is_running; then
        # Still the old name, but still answering; the next sync tries again.
        log_message "avahi-daemon did not exit; not restarting it"
        return 0
    fi
    # shellcheck disable=SC2086 # AVAHI_FLAGS is a list of words
    if ! "$AVAHI_BIN" $AVAHI_FLAGS; then
        log_message "avahi-daemon failed to start; retrying"
        _avahi_wait_gone
        # shellcheck disable=SC2086
        if ! "$AVAHI_BIN" $AVAHI_FLAGS; then
            log_message "avahi-daemon failed to start again"
            return 0
        fi
    fi
    echo "$_name" >"$AVAHI_NAME_FILE"
    log_message "avahi-daemon restarted as $_name.local"
}

start_mdns_process() {
    mdns_is_running && return 0

    # Game exit launches networkservices.sh twice about a second apart; only one may start mdnsd.
    # mkdir is atomic. A lock older than 10 s is from a start that was killed, so take it over.
    _now="$(date +%s)"
    if ! mkdir "$MDNS_START_LOCK" 2>/dev/null; then
        read -r _since 2>/dev/null <"$MDNS_START_LOCK/since" || _since=0
        [ $((_now - _since)) -gt 10 ] || return 0
        rm -rf "$MDNS_START_LOCK"
        mkdir "$MDNS_START_LOCK" 2>/dev/null || return 0
    fi
    echo "$_now" >"$MDNS_START_LOCK/since"
    # The other instance may have started it and released the lock just before we took it.
    if mdns_is_running; then
        rm -rf "$MDNS_START_LOCK"
        return 0
    fi

    _name="$(get_spruce_hostname)"
    log_message "Starting mDNS responder as $_name.local..."

    # mdnsd publishes the host record only alongside a service.
    mkdir -p "$MDNS_SERVICE_DIR"
    printf 'type _device-info._tcp\nport 9\n' >"$MDNS_SERVICE_DIR/device-info.service"

    # Overwrite any stale name; mdnsd's -w replaces it with the settled one.
    echo "$_name" >"$HOSTNAME_STATE_FILE"
    "$MDNS_BIN" -i wlan0 -H "$_name" -p "$MDNS_PID_FILE" -w "$HOSTNAME_STATE_FILE" "$MDNS_SERVICE_DIR"
    rm -rf "$MDNS_START_LOCK"
}

stop_mdns_process() {
    if mdns_is_running; then
        log_message "Shutting down mDNS responder..."
        # shellcheck disable=SC2046
        kill $(mdns_pids)
        # Wait for it to go, or a restart's start would see it and do nothing.
        _waited=0
        while mdns_is_running && [ "$_waited" -lt 20 ]; do
            sleep 0.1
            _waited=$((_waited + 1))
        done
        if mdns_is_running; then
            # shellcheck disable=SC2046
            kill -9 $(mdns_pids)
        fi
        # The file outlives mdnsd; don't leave a renamed (NAME-2) value behind.
        get_spruce_hostname >"$HOSTNAME_STATE_FILE"
    fi
}

sync_mdns_process() {
    if device_manages_own_wifi; then
        stop_mdns_process
        return 0
    fi
    # Never a second responder beside the firmware's; have it announce the spruce name instead.
    if avahi_is_running; then
        stop_mdns_process
        announce_via_avahi
        return 0
    fi
    # The link, not the internet: mdnsd binds -i wlan0 and mDNS never leaves the LAN.
    if mdns_services_wanted && iface_has_address wlan0; then
        start_mdns_process
    else
        stop_mdns_process
    fi
}

restart_mdns_process() {
    stop_mdns_process
    sync_mdns_process
}
