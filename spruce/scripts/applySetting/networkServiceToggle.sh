#!/bin/sh
# Apply a Network Settings service toggle (Enable Samba / Enable SSH /
# Enable WiFi File Transfer / Enable Syncthing) immediately, instead of
# waiting for networkservices.sh's own connect loop to notice on its next
# wake, or for a reboot.
#
# Usage: networkServiceToggle.sh <samba|ssh|sftpgo|syncthing> <True|False>
#
# Wired up as each setting's changeCmd. PyUI's set_menu_option() saves the
# newly-selected value to spruce-config.json before running changeCmd (see
# CfwSystemConfig.set_menu_option) and appends that value as the last
# argument, so $2 here is already current.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

SERVICE="$1"
ENABLED="$2"
MODE="$3"

case "$SERVICE" in
    samba)     PROC_NAME="smbd" ;;
    ssh)       PROC_NAME="$(get_ssh_service_name)" ;;
    sftpgo)    PROC_NAME="$(get_sftp_service_name)" ;;
    syncthing) PROC_NAME="syncthing" ;;
    *)
        log_message "networkServiceToggle: unknown service '$SERVICE'"
        exit 1
        ;;
esac

start_service() {
    case "$SERVICE" in
        samba)     start_samba_process ;;
        ssh)       start_ssh_process ;;
        sftpgo)    start_sftpgo_process ;;
        syncthing) start_syncthing_process ;;
    esac
}

stop_service() {
    case "$SERVICE" in
        samba)     stop_samba_process ;;
        ssh)       stop_ssh_process ;;
        sftpgo)    stop_sftpgo_process ;;
        syncthing) stop_syncthing_process ;;
    esac
}

apply_toggle() {
    if [ "$ENABLED" != "True" ]; then
        if pgrep "$PROC_NAME" >/dev/null; then
            log_message "networkServiceToggle: stopping $SERVICE (disabled via Settings)"
            stop_service
        fi
        return 0
    fi

    # Only start right away if WiFi is actually connected -- otherwise leave it to
    # networkservices.sh's own connect loop for whenever it does connect, same as
    # at boot (it reads this same setting fresh once the network comes up).
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 1 ] && network_is_connected true; then
        if ! pgrep "$PROC_NAME" >/dev/null; then
            log_message "networkServiceToggle: starting $SERVICE (enabled via Settings, WiFi already connected)"
            start_service
        fi
    fi
}

# Do the work detached, and one at a time per service.
#
# PyUI runs this through set_menu_option's subprocess.run(..., check=True),
# which blocks the UI thread until we exit. Two of the four services background
# themselves, but SSH does not: start_ssh_process polls for up to five seconds
# waiting for dropbear to take port 22, after a one-off RSA and ed25519 keygen
# the first time, which is seconds more on these CPUs. That froze the settings
# menu for the whole of it. Samba's smbpasswd is synchronous too, though quick.
#
# Serialised because backgrounding alone introduces a worse bug than the freeze:
# toggle SSH off while a start is still in its port-wait and stop_service finds
# nothing running, does nothing, and the start then completes - leaving the
# service up with the setting saying off. Each invocation carries the value it
# was called with, so running them in order lands on the right final state.
#
# The lock records its holder so a run killed mid-flight (PyUI restart, poweroff)
# cannot wedge every later toggle. Same approach as networkservices.sh's
# connect lock, which exists for the same reason.
# Hand off to a detached copy of ourselves and return, so PyUI is not kept
# waiting. Re-exec rather than a ( ) & subshell because the lock below records
# its holder's pid, and $$ inside a subshell is the PARENT's pid - the parent
# exits immediately here, so every later toggle would read the lock as stale and
# run concurrently, which is the exact race the lock exists to stop.
if [ "$MODE" != "--worker" ]; then
    # sh "$0" rather than "$0": the shebang already says sh, and this way the
    # hand-off does not depend on the exec bit surviving however the card was
    # written or copied.
    sh "$0" "$SERVICE" "$ENABLED" --worker >/dev/null 2>&1 &
    exit 0
fi

LOCK="/tmp/networkServiceToggle.$SERVICE"

holder_is_alive() {
    _pid="$(cat "$LOCK/pid" 2>/dev/null)"
    [ -n "$_pid" ] && [ -d "/proc/$_pid" ]
}

waited=0
while ! mkdir "$LOCK" 2>/dev/null; do
    if ! holder_is_alive; then
        log_message "networkServiceToggle: clearing stale $SERVICE lock"
        rm -rf "$LOCK"
        continue
    fi
    waited=$((waited + 1))
    if [ "$waited" -gt 60 ]; then
        log_message "networkServiceToggle: gave up waiting for the $SERVICE lock"
        exit 0
    fi
    sleep 0.5
done
echo "$$" >"$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM

apply_toggle
exit 0
