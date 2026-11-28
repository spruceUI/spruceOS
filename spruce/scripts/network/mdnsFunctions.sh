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

mdns_is_running() {
    pgrep -x mdnsd >/dev/null 2>&1
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
        kill $(pgrep -x mdnsd)
        # Wait for it to go, or a restart's start would see it and do nothing.
        _waited=0
        while mdns_is_running && [ "$_waited" -lt 20 ]; do
            sleep 0.1
            _waited=$((_waited + 1))
        done
        if mdns_is_running; then
            # shellcheck disable=SC2046
            kill -9 $(pgrep -x mdnsd)
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
