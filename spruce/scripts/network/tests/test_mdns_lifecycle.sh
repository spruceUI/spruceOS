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
PLATFORM_FAMILY=other
PLATFORM=Test
export HOSTNAME_STATE_FILE MDNS_BIN MDNS_SERVICE_DIR MDNS_PID_FILE MDNS_START_LOCK PLATFORM_FAMILY PLATFORM

# Fake responder: logs the state file contents it sees at launch, plus its args.
cat >"$MDNS_BIN" <<STUB
#!/bin/sh
echo "start state=\$(cat "$HOSTNAME_STATE_FILE" 2>/dev/null) args=\$*" >>"$LOG"
STUB
chmod +x "$MDNS_BIN"

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
    esac
}
iface_has_address() { [ "$1" = wlan0 ] && [ "$T_CONNECTED" = 1 ]; }
# The responder is LAN-only, so the internet check must never gate it.
network_is_connected() { echo "network_is_connected" >>"$LOG"; return 1; }
device_manages_own_wifi() { [ "$T_OWN_WIFI" = 1 ]; }
# T_UP_AFTER=N: reads as running from the (N+1)th pgrep on (another instance started it).
pgrep() {
    T_PGREPS=$((T_PGREPS + 1))
    [ "$T_RUNNING" = 1 ] || [ "$T_PGREPS" -gt "${T_UP_AFTER:-999}" ] || return 1
    echo 4242
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
    T_CONNECTED=1 T_OWN_WIFI=0 T_RUNNING=0 T_DIES=1 T_PGREPS=0 T_UP_AFTER=999
    unset samba_enabled ssh_enabled sftpgo_enabled syncthing_enabled
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

echo "PASS"
