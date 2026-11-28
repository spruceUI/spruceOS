#!/bin/sh
set -eu

script_dir="$(CDPATH="" cd -- "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/spruce-hostname.XXXXXX)"
trap 'find "$test_dir" -type f -exec rm -f -- {} +; find "$test_dir" -depth -type d -exec rmdir -- {} +' EXIT

# shellcheck source=/dev/null
. "$script_dir/hostnameFunctions.sh"

check() {
    label="$1"
    expected="$2"
    actual="$3"
    [ "$actual" = "$expected" ] || { echo "FAIL: $label: expected '$expected', got '$actual'"; exit 1; }
}

a62="$(printf 'a%.0s' $(seq 62))"
a63="$a62"a
a70="$(printf 'a%.0s' $(seq 70))"

check "mixed case and punctuation" "my-brick" "$(normalize_hostname "My Brick!")"
check "spaces become dashes" "spaced--out" "$(normalize_hostname "  spaced  out ")"
check "only dashes" "" "$(normalize_hostname "---")"
check "only punctuation" "" "$(normalize_hostname "!!!")"
check "truncate to 63" "$a63" "$(normalize_hostname "$a70")"
check "strip dash after truncation" "$a62" "$(normalize_hostname "${a62}-b")"

# model_host FAMILY [VAR=value ...]: run get_model_hostname and get_spruce_hostname in a clean env
model_host() {
    expected="$1"
    shift
    for fn in get_model_hostname get_spruce_hostname; do
        actual="$(env -i PATH="$PATH" "$@" sh -c ". '$script_dir/hostnameFunctions.sh'; $fn")"
        check "$fn $*" "$expected" "$actual"
    done
}

model_host spruce-mini PLATFORM_FAMILY=miyoomini MINI_MODEL=MIYOO_MINI
model_host spruce-miniv4 PLATFORM_FAMILY=miyoomini MINI_MODEL=MIYOO_MINI_V4
model_host spruce-miniplus PLATFORM_FAMILY=miyoomini MINI_MODEL=MIYOO_MINI_PLUS
model_host spruce-miniflip PLATFORM_FAMILY=miyoomini MINI_MODEL=MIYOO_MINI_FLIP
model_host spruce PLATFORM_FAMILY=miyoomini MINI_MODEL=
model_host spruce-rg40xxh PLATFORM_FAMILY=h700 BASEOS_TARGET=rg40xxh
model_host spruce PLATFORM_FAMILY=h700 BASEOS_TARGET= PLATFORM=AnbernicXX640480

printf 'v90s\r\n' > "$test_dir/device"
model_host spruce-v90s PLATFORM_FAMILY=oakmoss "MAGICX_DEVICE_FILE=$test_dir/device"
model_host spruce PLATFORM_FAMILY=oakmoss MAGICX_DEVICE_FILE=/nonexistent PLATFORM=Zero28
model_host spruce-a10miniv4 PLATFORM_FAMILY=darkmoss PLATFORM=A10MiniV4
model_host spruce-smartpros PLATFORM_FAMILY=tina-stock PLATFORM=SmartProS
model_host spruce PLATFORM= PLATFORM_FAMILY=

check "state file default" "/tmp/spruce_hostname" "$(env -i PATH="$PATH" sh -c ". '$script_dir/hostnameFunctions.sh'; echo \"\$HOSTNAME_STATE_FILE\"")"

# device_start_dhcp_client: stub udhcpc (prints args) and pgrep (not running), then source device.sh
dhcp_args() {
    env -i PATH="$PATH" "$@" sh -c "
        udhcpc() { echo \"\$*\"; }
        pgrep() { return 1; }
        . '$script_dir/../platform/device.sh'
        device_start_dhcp_client"
}

check "dhcp sends hostname" "-i wlan0 -b -t 5 -T 3 -x hostname:spruce-flip" "$(dhcp_args SPRUCE_HOSTNAME=spruce-flip)"
check "dhcp without hostname" "-i wlan0 -b -t 5 -T 3" "$(dhcp_args)"

# udhcpc -x fallback. The stub records each call's args to $test_dir/calls and exits with
# $UDHCPC_RC when -x is present (else 0); log_message records to $test_dir/log.
fb_stub() {
    cat <<STUB
        : > "$test_dir/calls"; : > "$test_dir/log"
        udhcpc() {
            echo "\$*" >> "$test_dir/calls"
            case " \$* " in *" -x "*) return \${UDHCPC_RC:-0};; esac
            return 0
        }
        pgrep() { return 1; }
        log_message() { echo "\$*" >> "$test_dir/log"; }
STUB
}
fb_run() {
    env -i PATH="$PATH" "$@" sh -c "
        $(fb_stub)
        . '$script_dir/../platform/device.sh'
        device_start_dhcp_client" || true
}
fb_extra=""
fb_checks() {
    base="-i wlan0 $fb_extra-b -t 5 -T 3"
    fb_run SPRUCE_HOSTNAME=spruce-flip UDHCPC_RC=0
    check "fb rc0 calls" "$base -x hostname:spruce-flip" "$(cat "$test_dir/calls")"
    check "fb rc0 log" "" "$(cat "$test_dir/log")"
    fb_run SPRUCE_HOSTNAME=spruce-flip UDHCPC_RC=1
    check "fb rc1 calls" "$base -x hostname:spruce-flip
$base" "$(cat "$test_dir/calls")"
    case "$(cat "$test_dir/log")" in *"retrying without it"*) ;; *) echo "FAIL: fb rc1 log"; exit 1;; esac
    fb_run SPRUCE_HOSTNAME=spruce-flip UDHCPC_RC=137
    check "fb rc137 calls" "$base -x hostname:spruce-flip" "$(cat "$test_dir/calls")"
    check "fb rc137 log" "" "$(cat "$test_dir/log")"
    fb_run UDHCPC_RC=1
    check "fb unset calls" "$base" "$(cat "$test_dir/calls")"
    check "fb unset log" "" "$(cat "$test_dir/log")"
}
fb_checks

# MiyooMini override: extract its hook (the file is not sourceable in isolation), run on top of device.sh
sed -n '/^device_start_dhcp_client() {/,/^}/p' "$script_dir/../platform/miyoomini/MiyooMini.sh" > "$test_dir/mini_hook.sh"
fb_run() {
    env -i PATH="$PATH" "$@" sh -c "
        $(fb_stub)
        . '$script_dir/../platform/device.sh'
        . '$test_dir/mini_hook.sh'
        device_start_dhcp_client" || true
}
fb_extra="-s /etc/init.d/udhcpc.script "
fb_checks

# trimui_a133p: extract its hook, point the log at the temp dir, run the sh -c wrapper with a stub
# udhcpc on PATH and a setsid stub that runs its arguments.
mkdir "$test_dir/bin"
cat > "$test_dir/bin/udhcpc" <<STUB
#!/bin/sh
echo "\$*" >> "$test_dir/calls"
case " \$* " in *" -x "*) exit \${UDHCPC_RC:-0};; esac
exit 0
STUB
printf '#!/bin/sh\nexec "$@"\n' > "$test_dir/bin/setsid"
chmod +x "$test_dir/bin/udhcpc" "$test_dir/bin/setsid"
sed -n '/^device_start_dhcp_client() {/,/^}/p' "$script_dir/../platform/tina-stock/trimui_a133p.sh" |
    sed "s#/tmp/spruce-dhcp.log#$test_dir/dhcp.log#g" > "$test_dir/a133_hook.sh"
a133_run() {
    : > "$test_dir/calls"; : > "$test_dir/dhcp.log"
    env -i PATH="$test_dir/bin:$PATH" "$@" sh -c "
        pgrep() { return 1; }
        . '$test_dir/a133_hook.sh'
        device_start_dhcp_client
        wait"
}
base="-i wlan0 -f -t 5 -T 3"
a133_run SPRUCE_HOSTNAME=spruce-flip UDHCPC_RC=0
check "a133 rc0 calls" "$base -x hostname:spruce-flip" "$(cat "$test_dir/calls")"
check "a133 rc0 log" "" "$(cat "$test_dir/dhcp.log")"
a133_run SPRUCE_HOSTNAME=spruce-flip UDHCPC_RC=1
check "a133 rc1 calls" "$base -x hostname:spruce-flip
$base" "$(cat "$test_dir/calls")"
case "$(cat "$test_dir/dhcp.log")" in *"retrying without it"*) ;; *) echo "FAIL: a133 rc1 log"; exit 1;; esac
a133_run SPRUCE_HOSTNAME=spruce-flip UDHCPC_RC=137
check "a133 rc137 calls" "$base -x hostname:spruce-flip" "$(cat "$test_dir/calls")"
a133_run UDHCPC_RC=1
check "a133 unset calls" "$base" "$(cat "$test_dir/calls")"

check "default device_set_hostname" "spruce-flip" "$(env -i PATH="$PATH" sh -c "
    hostname() { echo \"\$*\"; }
    . '$script_dir/../platform/device.sh'
    device_set_hostname spruce-flip")"

# wifi.sh apply_spruce_hostname: extracted (wifi.sh is not sourceable in isolation). A running
# mdnsd owns the state file, so it is written only when none is running.
sed -n '/^apply_spruce_hostname() {/,/^}/p' "$script_dir/wifi.sh" > "$test_dir/apply_host.sh"
apply_host() {
    printf 'spruce-flip-2\n' > "$test_dir/state"
    env -i PATH="$PATH" HOSTNAME_STATE_FILE="$test_dir/state" T_RUNNING="$1" sh -c "
        get_spruce_hostname() { echo spruce-flip; }
        device_set_hostname() { echo \"set \$1\"; }
        pgrep() { [ \"\$*\" = '-x mdnsd' ] && [ \"\$T_RUNNING\" = 1 ]; }
        . '$test_dir/apply_host.sh'
        apply_spruce_hostname
        echo \"exported \$SPRUCE_HOSTNAME\""
}
check "apply hostname, mdnsd running: calls" "set spruce-flip
exported spruce-flip" "$(apply_host 1)"
check "apply hostname, mdnsd running: state kept" "spruce-flip-2" "$(cat "$test_dir/state")"
check "apply hostname, no mdnsd: calls" "set spruce-flip
exported spruce-flip" "$(apply_host 0)"
check "apply hostname, no mdnsd: state written" "spruce-flip" "$(cat "$test_dir/state")"

echo "PASS"
