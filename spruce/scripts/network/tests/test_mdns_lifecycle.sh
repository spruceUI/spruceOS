#!/bin/sh
set -eu

script_dir="$(CDPATH="" cd -- "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/spruce-mdns.XXXXXX)"
trap 'find "$test_dir" -type f -exec rm -f -- {} +; find "$test_dir" -depth -type d -exec rmdir -- {} +' EXIT

LOG="$test_dir/log"
HOSTNAME_STATE_FILE="$test_dir/state"
MDNS_BIN="$test_dir/mdnsd"
MDNS_SERVICE_DIR="$test_dir/svc"
MDNS_PID_FILE="$test_dir/pid"
MDNS_START_LOCK="$test_dir/starting"
MDNS_PROC_DIR="$test_dir/proc"
AVAHI_BIN="$test_dir/avahi-daemon"
AVAHI_NAME_FILE="$test_dir/avahi_name"
PLATFORM_FAMILY=other
PLATFORM=Test
export HOSTNAME_STATE_FILE MDNS_BIN MDNS_SERVICE_DIR MDNS_PID_FILE MDNS_START_LOCK MDNS_PROC_DIR \
    AVAHI_BIN AVAHI_NAME_FILE PLATFORM_FAMILY PLATFORM

# 4242 is mdnsd; 4343 is a shell that only mentions its path, which "pgrep -f" also finds.
mkdir -p "$MDNS_PROC_DIR/4242" "$MDNS_PROC_DIR/4343"
printf '%s\0-i\0wlan0\0' "$MDNS_BIN" >"$MDNS_PROC_DIR/4242/cmdline"
printf 'sh\0-c\0sleep 1; %s\0' "$MDNS_BIN" >"$MDNS_PROC_DIR/4343/cmdline"

# Fake responder: logs the state file contents it sees at launch, plus its args.
cat >"$MDNS_BIN" <<STUB
#!/bin/sh
echo "start state=\$(cat "$HOSTNAME_STATE_FILE" 2>/dev/null) args=\$*" >>"$LOG"
STUB
chmod +x "$MDNS_BIN"

# Fake firmware avahi-daemon: running while avahi_up exists; --check reports that.
# avahi_linger=N: after -k it stays up for N more checks. avahi_fail=N: the next N starts fail.
# A start while it is still up is refused, as the real one does.
cat >"$AVAHI_BIN" <<STUB
#!/bin/sh
up="$test_dir/avahi_up" linger="$test_dir/avahi_linger" fail="$test_dir/avahi_fail"
case "\$1" in
    --check)
        [ -f "\$up" ] || exit 1
        if [ -f "$test_dir/avahi_dying" ]; then
            n=\$(cat "\$linger" 2>/dev/null || echo 0)
            if [ "\$n" -le 0 ]; then rm -f "\$up" "$test_dir/avahi_dying"; exit 1; fi
            echo \$((n - 1)) >"\$linger"
        fi
        exit 0 ;;
    -k) echo "avahi \$*" >>"$LOG"; : >"$test_dir/avahi_dying"
        [ -f "\$linger" ] || { rm -f "\$up" "$test_dir/avahi_dying"; }
        exit 0 ;;
esac
if [ -f "\$up" ]; then echo "avahi refused" >>"$LOG"; exit 1; fi
if [ "\$(cat "\$fail" 2>/dev/null || echo 0)" -gt 0 ]; then
    echo \$((\$(cat "\$fail") - 1)) >"\$fail"
    echo "avahi failed" >>"$LOG"; exit 1
fi
echo "avahi \$*" >>"$LOG"
: >"\$up"
STUB
chmod +x "$AVAHI_BIN"

# shellcheck source=/dev/null
. "$script_dir/hostnameFunctions.sh"
# shellcheck source=/dev/null
. "$script_dir/mdnsFunctions.sh"

# Stubs for helperFunctions / device.sh and process tools.
log_message() { :; }
get_config_value() {
    case "$1" in
        *enableSamba*) echo "$T_SAMBA" ;;
        *enableSSH*) echo "$T_SSH" ;;
        *enableSFTPGo*) echo "$T_SFTPGO" ;;
        *enableSyncthing*) echo "$T_SYNCTHING" ;;
        *enableOfflineProxy*) echo "$T_RAPROXY" ;;
        *hostnameSource*) echo spruce ;;
    esac
}
iface_has_address() { [ "$1" = wlan0 ] && [ "$T_CONNECTED" = 1 ]; }
# The responder is LAN-only, so the internet check must never gate it.
network_is_connected() { echo "network_is_connected" >>"$LOG"; return 1; }
device_manages_own_wifi() { [ "$T_OWN_WIFI" = 1 ]; }
# The RGSP's busybox pgrep: "-x mdnsd" finds nothing even while mdnsd runs; only the path does.
# T_UP_AFTER=N: reads as running from the (N+1)th pgrep on (another instance started it).
# Counted in a file: mdns_is_running calls pgrep in a subshell.
pgrep() {
    case "$*" in
        "-f $MDNS_BIN")
            T_PGREPS=$(($(cat "$test_dir/pgreps") + 1))
            echo "$T_PGREPS" >"$test_dir/pgreps"
            echo 4343
            [ "$T_RUNNING" = 1 ] || [ "$T_PGREPS" -gt "${T_UP_AFTER:-999}" ] || return 0
            echo 4242
            ;;
        *) return 1 ;;
    esac
}
# T_DIES=1: the process exits as soon as it is signalled.
kill() { echo "stop $*" >>"$LOG"; [ "${T_DIES:-0}" = 1 ] && T_RUNNING=0; return 0; }
sleep() { :; }

check() {
    [ "$3" = "$2" ] || { echo "FAIL: $1: expected '$2', got '$3'"; exit 1; }
}

count() { grep -c "^$1" "$LOG" || true; }

# run LABEL STARTS STOPS: sync with the current T_* values and count log lines.
run() {
    : >"$LOG"
    sync_mdns_process
    check "$1 (starts)" "$2" "$(count start)"
    check "$1 (stops)" "$3" "$(count stop)"
    check "$1 (no internet check)" "0" "$(count network_is_connected)"
}

reset() {
    T_SAMBA=False T_SSH=False T_SFTPGO=False T_SYNCTHING=False T_RAPROXY=False
    T_CONNECTED=1 T_OWN_WIFI=0 T_RUNNING=0 T_DIES=1 T_UP_AFTER=999
    echo 0 >"$test_dir/pgreps"
    unset samba_enabled ssh_enabled sftpgo_enabled syncthing_enabled
    rm -f "$test_dir/avahi_up" "$test_dir/avahi_fail" "$test_dir/avahi_linger" \
        "$test_dir/avahi_dying" "$AVAHI_NAME_FILE"
}

reset; T_RUNNING=1
run "all off, running" 0 1

reset; T_SSH=True
run "ssh on, connected, not running" 1 0

reset; T_SSH=True; T_RUNNING=1
run "ssh on, already running" 0 0

reset; T_SAMBA=True; T_RUNNING=1
run "samba on, ssh off, running" 0 0

reset; T_SSH=True; T_CONNECTED=0
run "ssh on, not connected" 0 0

reset; T_SSH=True; T_OWN_WIFI=1
run "ssh on, own wifi" 0 0

reset; T_SSH=True; T_OWN_WIFI=1; T_RUNNING=1
run "own wifi, running" 0 1

reset; T_RAPROXY=True
run "only raproxy on" 0 0

reset; T_SYNCTHING=True
run "syncthing on" 1 0

# networkservices.sh's already-read values win over the config (no jq).
reset; T_SSH=True
# shellcheck disable=SC2034 # read by mdns_services_wanted
samba_enabled=False ssh_enabled=False sftpgo_enabled=False syncthing_enabled=False
run "variables all off, config on" 0 0
reset
# shellcheck disable=SC2034
samba_enabled=False ssh_enabled=False sftpgo_enabled=True syncthing_enabled=False
run "variables sftpgo on, config off" 1 0
# Only some set (not networkservices.sh): read the config.
reset; T_SSH=True
# shellcheck disable=SC2034
samba_enabled=False
run "partial variables, config ssh on" 1 0

# Launch arguments and service file.
reset; T_SSH=True
: >"$LOG"
sync_mdns_process
check "args" "start state=spruce-test args=-i wlan0 -H spruce-test -p $MDNS_PID_FILE -w $HOSTNAME_STATE_FILE $MDNS_SERVICE_DIR" "$(cat "$LOG")"
check "service file" "type _device-info._tcp
port 9" "$(cat "$MDNS_SERVICE_DIR/device-info.service")"

# Start overwrites a stale name before launching (the stub saw it above).
echo "stale-name-2" >"$HOSTNAME_STATE_FILE"
reset; T_SSH=True
: >"$LOG"
start_mdns_process
check "start overwrites stale state" "start state=spruce-test args=-i wlan0 -H spruce-test -p $MDNS_PID_FILE -w $HOSTNAME_STATE_FILE $MDNS_SERVICE_DIR" "$(cat "$LOG")"

# Stop writes the requested name back after stopping a responder.
reset; T_RUNNING=1
echo "spruce-test-2" >"$HOSTNAME_STATE_FILE"
stop_mdns_process
check "stop restores state (running)" "spruce-test" "$(cat "$HOSTNAME_STATE_FILE")"
# With nothing running there is nothing to undo: the file is left alone.
reset
echo "spruce-test-3" >"$HOSTNAME_STATE_FILE"
touch -t 200001010000 "$HOSTNAME_STATE_FILE"
before="$(ls -l "$HOSTNAME_STATE_FILE")"
stop_mdns_process
check "stop leaves state (not running)" "spruce-test-3" "$(cat "$HOSTNAME_STATE_FILE")"
check "stop leaves state mtime (not running)" "$before" "$(ls -l "$HOSTNAME_STATE_FILE")"

# Start lock: released after a start.
reset; T_SSH=True
run "start releases lock" 1 0
check "lock gone after start" "no" "$([ -d "$MDNS_START_LOCK" ] && echo yes || echo no)"
# Another instance is mid-start: do nothing, leave its lock.
reset; T_SSH=True
mkdir "$MDNS_START_LOCK"; date +%s >"$MDNS_START_LOCK/since"
run "lock held" 0 0
check "held lock kept" "yes" "$([ -d "$MDNS_START_LOCK" ] && echo yes || echo no)"
# A lock left by a killed start (old timestamp, or none) is taken over.
reset; T_SSH=True
echo 0 >"$MDNS_START_LOCK/since"
run "stale lock" 1 0
check "stale lock gone" "no" "$([ -d "$MDNS_START_LOCK" ] && echo yes || echo no)"
reset; T_SSH=True
mkdir "$MDNS_START_LOCK"
run "lock without timestamp" 1 0
# The other instance started it and released the lock just before we took it.
reset; T_SSH=True; T_UP_AFTER=1
run "started by other instance" 0 0
check "lock released when other started" "no" "$([ -d "$MDNS_START_LOCK" ] && echo yes || echo no)"

# restart = stop (waiting for exit), then start: exactly one start.
reset; T_SSH=True; T_RUNNING=1; T_DIES=1
: >"$LOG"
restart_mdns_process
check "restart stops" "1" "$(count stop)"
check "restart starts" "1" "$(count start)"

# A process that ignores SIGTERM gets SIGKILL.
reset; T_RUNNING=1; T_DIES=0
: >"$LOG"
stop_mdns_process
check "term then kill -9" "stop 4242
stop -9 4242" "$(cat "$LOG")"

# Exact pids, not the shell that mentions the path.
reset; T_RUNNING=1
check "pids" "4242" "$(mdns_pids)"
reset
check "pids (not running)" "" "$(mdns_pids)"

# Firmware avahi-daemon running: never start mdnsd; restart avahi once for the spruce name.
avahi_restart="avahi -k
avahi --daemonize --no-drop-root --no-proc-title"
reset; T_SSH=True; : >"$test_dir/avahi_up"
run "avahi, no name file" 0 0
check "avahi, no name file: restarted" "$avahi_restart" "$(grep '^avahi' "$LOG")"
check "avahi, no name file: name file" "spruce-test" "$(cat "$AVAHI_NAME_FILE")"
check "avahi, no name file: state file" "spruce-test" "$(cat "$HOSTNAME_STATE_FILE")"
check "avahi still running" "yes" "$([ -f "$test_dir/avahi_up" ] && echo yes || echo no)"
run "avahi, name unchanged" 0 0
check "avahi, name unchanged: not restarted" "" "$(grep '^avahi' "$LOG" || true)"
echo "old-name" >"$AVAHI_NAME_FILE"
run "avahi, name changed" 0 0
check "avahi, name changed: restarted" "$avahi_restart" "$(grep '^avahi' "$LOG")"
check "avahi, name changed: name file" "spruce-test" "$(cat "$AVAHI_NAME_FILE")"
# Not gated on services or the link: avahi announces either way, so it must use our name.
reset; T_CONNECTED=0; : >"$test_dir/avahi_up"
run "avahi, services off, no link" 0 0
check "avahi, services off: restarted" "$avahi_restart" "$(grep '^avahi' "$LOG")"
# A leftover mdnsd beside avahi is stopped.
reset; T_SSH=True; T_RUNNING=1; : >"$test_dir/avahi_up"
run "avahi and mdnsd" 0 1
check "avahi and mdnsd: stopped mdnsd" "stop 4242" "$(grep '^stop' "$LOG")"
# restart_mdns_process (hostname.sh's path for mdnsd) also hands over to avahi.
reset; T_SSH=True; : >"$test_dir/avahi_up"; echo "old-name" >"$AVAHI_NAME_FILE"
: >"$LOG"
restart_mdns_process
check "avahi via restart: no mdnsd" "0" "$(count start)"
check "avahi via restart: restarted" "$avahi_restart" "$(grep '^avahi' "$LOG")"
# Slow to exit: the start comes only once it is down (5 checks later), never refused.
reset; : >"$test_dir/avahi_up"; echo 5 >"$test_dir/avahi_linger"
run "avahi slow exit" 0 0
check "avahi slow exit: started after it went" "$avahi_restart" "$(grep '^avahi' "$LOG")"
check "avahi slow exit: name file" "spruce-test" "$(cat "$AVAHI_NAME_FILE")"
# Never exits within the wait: no start (it would fail), still running, no name file.
reset; : >"$test_dir/avahi_up"; echo 50 >"$test_dir/avahi_linger"
run "avahi never exits" 0 0
check "avahi never exits: no start" "avahi -k" "$(grep '^avahi' "$LOG")"
check "avahi never exits: still running" "yes" "$([ -f "$test_dir/avahi_up" ] && echo yes || echo no)"
check "avahi never exits: no name file" "no" "$([ -f "$AVAHI_NAME_FILE" ] && echo yes || echo no)"
# One failed start is retried.
reset; : >"$test_dir/avahi_up"; echo 1 >"$test_dir/avahi_fail"
run "avahi start fails once" 0 0
check "avahi start fails once: retried" "avahi -k
avahi failed
avahi --daemonize --no-drop-root --no-proc-title" "$(grep '^avahi' "$LOG")"
check "avahi start fails once: name file" "spruce-test" "$(cat "$AVAHI_NAME_FILE")"
# Both fail: no name file, so the next sync tries again.
reset; : >"$test_dir/avahi_up"; echo 2 >"$test_dir/avahi_fail"
run "avahi start fails twice" 0 0
check "avahi start fails twice: two tries" "2" "$(grep -c '^avahi failed' "$LOG")"
check "avahi start fails twice: no name file" "no" "$([ -f "$AVAHI_NAME_FILE" ] && echo yes || echo no)"
# Devices that manage their own WiFi: no responder work, avahi untouched.
reset; T_SSH=True; T_OWN_WIFI=1; : >"$test_dir/avahi_up"
run "avahi, own wifi" 0 0
check "avahi, own wifi: untouched" "" "$(grep '^avahi' "$LOG" || true)"
# No avahi binary: a process merely named like it does not count.
reset; T_SSH=True; : >"$test_dir/avahi_up"
AVAHI_BIN="$test_dir/missing-avahi-daemon"
run "avahi binary missing" 1 0
AVAHI_BIN="$test_dir/avahi-daemon"

echo "PASS"
