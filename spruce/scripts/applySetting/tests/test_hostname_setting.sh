#!/bin/sh
set -eu

script_dir="$(CDPATH="" cd -- "$(dirname "$0")/.." && pwd)"
repo="$(CDPATH="" cd -- "$script_dir/../../.." && pwd)"
test_dir="$(mktemp -d /tmp/spruce-hostname-setting.XXXXXX)"
trap 'find "$test_dir" -type f -exec rm -f -- {} +; find "$test_dir" -depth -type d -exec rmdir -- {} +' EXIT
sdcard="$test_dir/SDCARD"
cfg="$sdcard/Saves/spruce/spruce-config.json"
calls="$test_dir/calls"

mkdir -p "$sdcard/spruce/scripts/network" "$sdcard/Saves/spruce"

# Stubs: the real get_config_value, and recorders for everything with side effects.
cat >"$sdcard/spruce/scripts/helperFunctions.sh" <<EOF2
PLATFORM_FAMILY=test
PLATFORM=TESTBOX
log_message() { :; }
get_config_value() { jq -r "\${1} // \"\$2\"" "$cfg"; }
device_set_hostname() { echo "device_set_hostname \$1" >>"$calls"; }
network_is_connected() { echo network_is_connected >>"$calls"; }
EOF2
cat >"$sdcard/spruce/scripts/network/mdnsFunctions.sh" <<EOF2
mdns_is_running() { [ -f "$test_dir/running" ]; }
restart_mdns_process() { echo restart_mdns_process >>"$calls"; }
EOF2
cp "$script_dir/../network/hostnameFunctions.sh" "$sdcard/spruce/scripts/network/"
sed "s@/mnt/SDCARD@$sdcard@g" "$script_dir/hostname.sh" >"$test_dir/hostname.sh"

export HOSTNAME_STATE_FILE="$test_dir/state"
export DEVICE_HOSTNAME_FILE="$test_dir/device_name"
export KERNEL_HOSTNAME_FILE="$test_dir/kernel_name"

check() {
    [ "$3" = "$2" ] || { echo "FAIL: $1: expected '$2', got '$3'"; exit 1; }
}

selected() { jq -r '.menuOptions."Network Settings".hostname.selected' "$cfg"; }

# prep LABEL TYPED RUNNING(0|1) [SOURCE]: fresh config holding TYPED (and SOURCE, default Custom),
# as PyUI saves it before the call. The changeCmd is read from the shipped config, as PyUI does.
prep() {
    jq --arg v "$2" --arg s "${4:-Custom}" '.menuOptions."Network Settings".hostname.selected = $v
        | .menuOptions."Network Settings".hostnameSource.selected = $s' \
        "$repo/Saves/spruce/spruce-config.json" >"$cfg"
    rm -f "$calls" "$test_dir/running" "$HOSTNAME_STATE_FILE" "$DEVICE_HOSTNAME_FILE"
    printf 'firmware-box\n' >"$KERNEL_HOSTNAME_FILE"
    : >"$calls"
    if [ "$3" = 1 ]; then : >"$test_dir/running"; fi
}
run() {
    prep "$@"
    sh "$test_dir/hostname.sh" name "$2"
}

run "typed name" "My Brick!" 1
check "typed: selected" "my-brick" "$(selected)"
check "typed: state file" "my-brick" "$(cat "$HOSTNAME_STATE_FILE")"
check "typed: calls" "device_set_hostname my-brick
restart_mdns_process" "$(cat "$calls")"

run "nothing valid" "!!!" 1
check "invalid: selected" "" "$(selected)"
check "invalid: state file" "spruce-testbox" "$(cat "$HOSTNAME_STATE_FILE")"
check "invalid: device_set_hostname" "device_set_hostname spruce-testbox
restart_mdns_process" "$(cat "$calls")"

run "responder not running" "My Brick!" 0
check "not running: selected" "my-brick" "$(selected)"
check "not running: state file" "my-brick" "$(cat "$HOSTNAME_STATE_FILE")"
check "not running: no restart" "device_set_hostname my-brick" "$(cat "$calls")"

# An already-normalised value must not rewrite the config.
run "unchanged" "my-brick" 1
touch -t 200001010000 "$cfg"
before="$(ls -l "$cfg")"
sh "$test_dir/hostname.sh" name "my-brick"
check "unchanged: config untouched" "$before" "$(ls -l "$cfg")"
check "unchanged: selected" "my-brick" "$(selected)"

# Shipped changeCmds: the source passes its value alone, the custom name passes "name" first.
check "source changeCmd" "/mnt/SDCARD/spruce/scripts/applySetting/hostname.sh" \
    "$(jq -r '.menuOptions."Network Settings".hostnameSource.changeCmd' "$repo/Saves/spruce/spruce-config.json")"
check "name changeCmd" "/mnt/SDCARD/spruce/scripts/applySetting/hostname.sh name" \
    "$(jq -r '.menuOptions."Network Settings".hostname.changeCmd' "$repo/Saves/spruce/spruce-config.json")"

# Changing the source leaves the typed name alone, even one that normalisation would change.
for src in Device spruce Custom; do
    prep "source $src" "My Brick!" 1 "$src"
    sh "$test_dir/hostname.sh" "$src"
    check "source $src: typed name untouched" "My Brick!" "$(selected)"
done
prep "source Device" "My Brick!" 1 Device
sh "$test_dir/hostname.sh" Device
check "source Device: state file" "firmware-box" "$(cat "$HOSTNAME_STATE_FILE")"
check "source Device: calls" "device_set_hostname firmware-box
restart_mdns_process" "$(cat "$calls")"
prep "source spruce" "My Brick!" 0 spruce
sh "$test_dir/hostname.sh" spruce
check "source spruce: state file" "spruce-testbox" "$(cat "$HOSTNAME_STATE_FILE")"
check "source spruce: calls" "device_set_hostname spruce-testbox" "$(cat "$calls")"
prep "source Custom" "My Brick!" 0 Custom
sh "$test_dir/hostname.sh" Custom
check "source Custom: calls" "device_set_hostname my-brick" "$(cat "$calls")"

# Switching source at runtime: Custom is applied first (kernel name becomes the custom one),
# then Device must still apply the firmware name.
prep "runtime switch" "Living Room" 0 Custom
sh "$test_dir/hostname.sh" Custom
printf 'living-room\n' >"$KERNEL_HOSTNAME_FILE"
jq '.menuOptions."Network Settings".hostnameSource.selected = "Device"' "$cfg" >"$cfg.tmp" && mv "$cfg.tmp" "$cfg"
: >"$calls"
sh "$test_dir/hostname.sh" Device
check "runtime switch: Device applies firmware name" "device_set_hostname firmware-box" "$(cat "$calls")"

echo "PASS"
