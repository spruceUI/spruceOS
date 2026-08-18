#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SSH_DIR="/mnt/SDCARD/spruce/bin/SSH"
SSH_KEYS="/mnt/SDCARD/spruce/etc/ssh/keys"
SSH_SERVICE_NAME=$(get_ssh_service_name)

dropbear_keygen() {
    key_type="$1"
    key_file="$2"

    [ -f "$key_file" ] && return 0

    if ! keygen_out="$($SSH_DIR/bin/dropbearmulti dropbearkey -t "$key_type" -f "$key_file" 2>&1)"; then
        log_message "SSH: failed to generate $key_type host key - $keygen_out"
        return 1
    fi
    log_message "SSH: generated $key_type host key at $key_file"
    return 0
}

dropbear_generate_keys() {
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    dropbear_keygen rsa "$SSH_KEYS/dropbear_rsa_host_key"
    # ed25519 rather than dss: dropbear 2025.88 answers "Unknown key type 'dss'".
    # DSS was dropped upstream, leaving rsa, ecdsa and ed25519.
    dropbear_keygen ed25519 "$SSH_KEYS/dropbear_ed25519_host_key"
    return 0
}

# The pid listening on port 22, or empty.
#
# Used in place of a name-based kill for two reasons: busybox killall takes an
# exact process name and ours is "dropbearmulti", so a name-based kill of
# "dropbear" is one mistake away from shooting ourselves; and dropbear's session
# children share the daemon's cmdline exactly, so only the listening socket
# identifies the one process actually in our way. Killing just the listener also
# leaves established sessions alone, so taking the port over does not disconnect
# whoever is already logged in.
ssh_listener_pid() {
    netstat -ltnp 2>/dev/null |
        awk '$4 ~ /:22$/ { split($NF, a, "/"); if (a[1] ~ /^[0-9]+$/) { print a[1]; exit } }'
}

# True if the given pid is spruce's own SSH daemon.
ssh_pid_is_ours() {
    ours_cmdline="$(tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null)"
    case "$ours_cmdline" in
    *dropbearmulti* | *"$SSH_DIR"*) return 0 ;;
    esac
    return 1
}

# Clear port 22 of anything that is not ours.
#
# Some devices ship an sshd that runs at startup. BaseOS goes further and starts
# its own dropbear from /etc/init.d/dev, with its own keys in /data/dropbear -
# which is why spruce's SSH has never actually been the daemon answering on
# these devices, and why the enableSSH setting could not turn SSH off there.
stop_foreign_ssh() {
    systemctl stop sshd 2>/dev/null
    killall -9 sshd 2>/dev/null

    foreign_pid="$(ssh_listener_pid)"
    if [ -n "$foreign_pid" ] && ! ssh_pid_is_ours "$foreign_pid"; then
        log_message "SSH: port 22 held by a foreign daemon (pid $foreign_pid), stopping it"
        kill -9 "$foreign_pid" 2>/dev/null
        sleep 1
    fi
}

start_ssh_process() {
    log_message "Starting $SSH_SERVICE_NAME..."
    if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
        # Generate here rather than trusting firstboot to have done it. firstboot
        # has never run on some platforms, and a keyless dropbear exits 1 with no
        # output at all, so the failure is otherwise completely silent.
        dropbear_generate_keys

        stop_foreign_ssh

        $SSH_DIR/bin/dropbearmulti dropbear \
            -r "$SSH_KEYS/dropbear_rsa_host_key" \
            -r "$SSH_KEYS/dropbear_ed25519_host_key" \
            -c "$SSH_DIR/dropbear-wrapper.sh" &

        # Backgrounded, so nothing above can report failure. Confirm we actually
        # took the port. There is deliberately no fallback to the system daemon:
        # a broken takeover should be obvious rather than masked by SSH that
        # still happens to work.
        wait_count=0
        while [ "$wait_count" -lt 10 ]; do
            started_pid="$(ssh_listener_pid)"
            if [ -n "$started_pid" ] && ssh_pid_is_ours "$started_pid"; then
                log_message "SSH: dropbearmulti listening on port 22 (pid $started_pid)"
                return 0
            fi
            sleep 0.5
            wait_count=$((wait_count + 1))
        done

        log_message "SSH ERROR: dropbearmulti did not take port 22 - SSH is DOWN. Check that host keys exist in $SSH_KEYS."
        return 1
    else # sshd
        systemctl start sshd
    fi
}

stop_ssh_process() {
    log_message "Shutting down ssh..."
    # Stop all forms of ssh
    systemctl stop sshd 2>/dev/null
    killall -9 sshd 2>/dev/null
    killall -9 dropbearmulti 2>/dev/null || true

    # On BaseOS the system's own dropbear survives the above and keeps answering,
    # so without this "SSH off" would leave root SSH open while the UI says it is
    # closed.
    remaining_pid="$(ssh_listener_pid)"
    if [ -n "$remaining_pid" ]; then
        log_message "SSH: port 22 still held by pid $remaining_pid, stopping it"
        kill -9 "$remaining_pid" 2>/dev/null
    fi
}
