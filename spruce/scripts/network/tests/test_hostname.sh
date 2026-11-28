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

# Stub get_config_value: TEST_SOURCE answers hostnameSource, TEST_USER_NAME answers hostname.
CFG_STUB='get_config_value() { case "$1" in *hostnameSource*) printf "%s" "$TEST_SOURCE";; *) printf "%s" "$TEST_USER_NAME";; esac; }'

# model_host FAMILY [VAR=value ...]: run get_model_hostname and get_spruce_hostname (source spruce)
# in a clean env
model_host() {
    expected="$1"
    shift
    for fn in get_model_hostname get_spruce_hostname; do
        actual="$(env -i PATH="$PATH" TEST_SOURCE=spruce "$@" sh -c ". '$script_dir/hostnameFunctions.sh'; $CFG_STUB; $fn")"
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

# user_host EXPECTED [VAR=value ...]: get_spruce_hostname with source Custom and name $TEST_USER_NAME
user_host() {
    expected="$1"
    shift
    actual="$(env -i PATH="$PATH" TEST_SOURCE=Custom "$@" sh -c ". '$script_dir/hostnameFunctions.sh'; $CFG_STUB; get_spruce_hostname")"
    check "user name $*" "$expected" "$actual"
}

user_host living-room TEST_USER_NAME="Living Room"
user_host spruce-flip PLATFORM_FAMILY=tina-stock PLATFORM=Flip TEST_USER_NAME="!!!"
user_host spruce-flip PLATFORM_FAMILY=tina-stock PLATFORM=Flip TEST_USER_NAME="   "
user_host spruce-flip PLATFORM_FAMILY=tina-stock PLATFORM=Flip TEST_USER_NAME=

# source_host EXPECTED SOURCE NAME: get_spruce_hostname in one shell that shares the capture file
# $test_dir/captured and the kernel name file $test_dir/kernel (a model of spruce-flip).
source_host() {
    env -i PATH="$PATH" PLATFORM_FAMILY=tina-stock PLATFORM=Flip \
        DEVICE_HOSTNAME_FILE="$test_dir/captured" KERNEL_HOSTNAME_FILE="$test_dir/kernel" \
        TEST_SOURCE="$1" TEST_USER_NAME="$2" sh -c ". '$script_dir/hostnameFunctions.sh'; $CFG_STUB; get_spruce_hostname"
}
fresh_boot() { rm -f "$test_dir/captured"; printf '%s\n' "$1" > "$test_dir/kernel"; }

check "device file default" "/tmp/spruce_device_hostname" "$(env -i PATH="$PATH" sh -c ". '$script_dir/hostnameFunctions.sh'; echo \"\$DEVICE_HOSTNAME_FILE\"")"
check "kernel file default" "/proc/sys/kernel/hostname" "$(env -i PATH="$PATH" sh -c ". '$script_dir/hostnameFunctions.sh'; echo \"\$KERNEL_HOSTNAME_FILE\"")"

fresh_boot "Miyoo Flip"
check "device: normalised firmware name" "miyoo-flip" "$(source_host Device "")"
check "device: captured file" "miyoo-flip" "$(cat "$test_dir/captured")"
printf 'spruce-flip\n' > "$test_dir/kernel"
check "device: second call uses the file" "miyoo-flip" "$(source_host Device "")"
check "missing source is Device" "miyoo-flip" "$(source_host "" "")"
check "unknown source is Device" "miyoo-flip" "$(source_host Bogus "")"
check "device ignores custom name" "miyoo-flip" "$(source_host Device "Living Room")"
check "spruce: model name despite custom name" "spruce-flip" "$(source_host spruce "Living Room")"
check "custom: custom name" "living-room" "$(source_host Custom "Living Room")"
check "custom: empty falls back to model" "spruce-flip" "$(source_host Custom "")"

# The firmware name is recorded whatever the source, so a later switch to Device still finds it.
fresh_boot "Miyoo Flip"
check "custom first" "living-room" "$(source_host Custom "Living Room")"
printf 'living-room\n' > "$test_dir/kernel"
check "switch to Device after Custom" "miyoo-flip" "$(source_host Device "Living Room")"
fresh_boot "Miyoo Flip"
check "spruce first" "spruce-flip" "$(source_host spruce "")"
printf 'spruce-flip\n' > "$test_dir/kernel"
check "switch to Device after spruce" "miyoo-flip" "$(source_host Device "")"

for fw in localhost "(none)" none localhost-localdomain "" "!!!"; do
    fresh_boot "$fw"
    check "device: firmware '$fw' uses model" "spruce-flip" "$(source_host Device "")"
    check "device: firmware '$fw' captured once" "spruce-flip" "$(cat "$test_dir/captured")"
    printf 'real\n' > "$test_dir/kernel"
    check "device: firmware '$fw' stays captured" "spruce-flip" "$(source_host Device "")"
done
rm -f "$test_dir/kernel" "$test_dir/captured"
check "device: no kernel file uses model" "spruce-flip" "$(source_host Device "")"

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
# pgrep as the RGSP's busybox: "-x mdnsd" finds nothing, only the binary's path does.
mkdir -p "$test_dir/proc/4242"
printf '%s\0-i\0wlan0\0' "$test_dir/mdnsd" > "$test_dir/proc/4242/cmdline"
apply_host() {
    printf 'spruce-flip-2\n' > "$test_dir/state"
    env -i PATH="$PATH" HOSTNAME_STATE_FILE="$test_dir/state" T_RUNNING="$1" \
        MDNS_BIN="$test_dir/mdnsd" MDNS_PROC_DIR="$test_dir/proc" sh -c "
        get_spruce_hostname() { echo spruce-flip; }
        device_set_hostname() { echo \"set \$1\"; }
        pgrep() { [ \"\$*\" = \"-f \$MDNS_BIN\" ] && [ \"\$T_RUNNING\" = 1 ] && echo 4242; }
        . '$script_dir/mdnsFunctions.sh'
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
