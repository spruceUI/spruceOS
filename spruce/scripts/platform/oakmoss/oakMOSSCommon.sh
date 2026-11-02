#!/bin/sh

# The oakMOSS base, what every oakMOSS chip shares, under each brand's layer (MagicXCommon.sh, PowkiddyCommon.sh,
# the Brick's in BrickOakMOSS.sh) and the boards. The board's cfg names its chip (PLATFORM_CHIP); that chip's
# oakMOSS layer (oakmoss_a133p.sh) holds what depends on the chip and its base image, over the chip file shared
# with other bases (platform/a133p.sh). See platform/README.md.

# Every chip layer defines these, which the base below calls: the chip's own device_init steps, the base
# image's radio service handed to spruce, the codec's volume.
oakmoss_chip_init() {
    log_message "Missing oakmoss_chip_init function"
}

oakmoss_disown_base_supplicant() {
    log_message "Missing oakmoss_disown_base_supplicant function"
}

oakmoss_apply_volume() {
    log_message "Missing oakmoss_apply_volume function"
}

if [ -n "$PLATFORM_CHIP" ] && [ -f "/mnt/SDCARD/spruce/scripts/platform/oakmoss/oakmoss_$PLATFORM_CHIP.sh" ]; then
    . "/mnt/SDCARD/spruce/scripts/platform/oakmoss/oakmoss_$PLATFORM_CHIP.sh"
else
    echo "oakMOSS: $PLATFORM.cfg names no oakMOSS chip layer (PLATFORM_CHIP='$PLATFORM_CHIP')" >&2
fi

# The board (zero28, xu20, v90s, brick...), from the base image's marker. Images without one
# predate the marker and are Zero 28 (Moss-zero28 itself).
oakmoss_model() {
    m=$(tr -d '\r\n' < /usr/magicx/device 2>/dev/null)
    echo "${m:-zero28}"
}

# oakMOSS release updates (App/-FirmwareUpdate-/oakmossUpdate.sh). /usr/magicx/version holds a release tag
# (v0.6.0-beta.1) or a tag plus commits (v0.5.0-beta.2-43-gd3e0f8f); images from v0.5 on install an .omupd.
oakmoss_installed_version() {
    tr -d '\r\n' < /usr/magicx/version 2>/dev/null
}

oakmoss_can_update() {
    [ -n "$(oakmoss_installed_version)" ] && [ -x /usr/magicx/bin/oakmoss-update.sh ]
}

# A fixed-width key: a beta sorts below its release, and a build past a tag above that tag.
oakmoss_version_key() {
    printf '%s\n' "$1" | sed 's/^[vV]//' | awk -F- '{
        split($1, v, "."); beta = 999999; dev = 0
        for (i = 2; i <= NF; i++) {
            if ($i ~ /^beta\.[0-9]+$/) { sub(/^beta\./, "", $i); beta = $i }
            else if ($i ~ /^[0-9]+$/) dev = $i
        }
        printf "%04d%04d%04d%06d%06d\n", v[1], v[2], v[3], beta, dev }'
}

# True when oakMOSS version $1 is older than $2.
oakmoss_version_older() {
    _a=$(oakmoss_version_key "$1"); _b=$(oakmoss_version_key "$2")
    [ "$_a" != "$_b" ] && [ "$(printf '%s\n%s\n' "$_a" "$_b" | sort | head -n 1)" = "$_a" ]
}

local_fw_update_file() {
    oakmoss_can_update && ls /mnt/SDCARD/oakmoss-"$(oakmoss_model)"-*.omupd 2>/dev/null | sort | tail -n 1
}

check_if_fw_needs_update() {
    oakmoss_can_update || { echo "false"; return; }
    _want="$(github_latest_version spruceUI/oakMOSS)" || { echo "false"; return; }
    oakmoss_version_older "$(oakmoss_installed_version)" "$_want" && echo "true" || echo "false"
}

# An oakMOSS image that carries its own library set (/usr/lib/oakmoss) gets it in the Flip libraries' place,
# and no Flip library directory stays on either path. Without it, a cfg that defaults to the set falls back
# to its OAKMOSS_FLIP_LD_PATH / OAKMOSS_FLIP_PORTS_PATH; any other cfg keeps its paths.
OAKMOSS_LIBS=${OAKMOSS_LIBS:-/usr/lib/oakmoss}
oakmoss_libs_paths() {
    if [ -d "$OAKMOSS_LIBS" ]; then
        LD_LIBRARY_PATH=$(oakmoss_libs_swap "$LD_LIBRARY_PATH" "$OAKMOSS_LIBS")
        PORTS_LD_LIBRARY_PATH=$(oakmoss_libs_swap "$PORTS_LD_LIBRARY_PATH" "$OAKMOSS_LIBS")
    else
        LD_LIBRARY_PATH=${OAKMOSS_FLIP_LD_PATH:-$LD_LIBRARY_PATH}
        PORTS_LD_LIBRARY_PATH=${OAKMOSS_FLIP_PORTS_PATH:-$PORTS_LD_LIBRARY_PATH}
    fi
    export LD_LIBRARY_PATH PORTS_LD_LIBRARY_PATH
}

# oakmoss_libs_swap <path list> <set dir>: the Flip library slot (spruce/flip/lib, or the userland
# tiers' spruce/aarch64/<NNN>/flip/lib) becomes the set's directory; every other Flip directory goes.
oakmoss_libs_swap() {
    _out=""
    _rest="$1:"
    while [ -n "$_rest" ]; do
        _e=${_rest%%:*}
        _rest=${_rest#*:}
        case "$_e" in
            /mnt/SDCARD/spruce/flip/lib | /mnt/SDCARD/spruce/flip/lib/ | \
            /mnt/SDCARD/spruce/aarch64/*/flip/lib | /mnt/SDCARD/spruce/aarch64/*/flip/lib/) _e=$2 ;;
            /mnt/SDCARD/spruce/flip/* | /mnt/SDCARD/spruce/*/flip/* | "") continue ;;
        esac
        _out=${_out:+$_out:}$_e
    done
    echo "$_out"
}

# Sourced right after the platform cfg (helperFunctions.sh), so every caller sees the swapped paths.
oakmoss_libs_paths

# First /dev/input/eventN whose kernel name matches one of the patterns.
oakmoss_find_event_by_name() {
    for d in /sys/class/input/event*; do
        n=$(tr -d '\n' < "$d/device/name" 2>/dev/null) || continue
        for pat in "$@"; do
            # shellcheck disable=SC2254  # the pattern is meant to glob
            case "$n" in $pat) echo "/dev/input/$(basename "$d")"; return 0 ;; esac
        done
    done
    return 1
}

# The touchscreen node. The base image's tslib hint is authoritative when it exists;
# otherwise the first node advertising ABS_MT_POSITION_X, then a name match.
oakmoss_touch_event_path() {
    p=$(sed -n 's/^\(export \)\{0,1\}TSLIB_TSDEVICE=//p' /etc/tslib-env.sh 2>/dev/null | head -1 | tr -d '"')
    [ -n "$p" ] && [ -e "$p" ] && { echo "$p"; return 0; }
    for d in /sys/class/input/event*; do
        abs=$(cat "$d/device/capabilities/abs" 2>/dev/null) || continue
        low=${abs##* }
        [ -n "$low" ] || continue
        if [ $(( 0x$low >> 53 & 1 )) -eq 1 ]; then
            echo "/dev/input/$(basename "$d")"
            return 0
        fi
    done
    oakmoss_find_event_by_name "*[Tt]ouch*" "*ts*" "*gt9*" "*ft5*" "*goodix*" "*[Ff]ocal*" "*hyn*" "*cst*"
}

# trimui's runtime_mounts_a133p also runs spruce/brick/sdl2/bind.sh, which binds
# TrimUI's stock SDL2 into the card; PyUI on oakMOSS loads /usr/magicx/lib directly.
oakmoss_runtime_mounts() {
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    wait
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI
}

# Each brand's layer defines these three, which device_init below calls: the input nodes by its pad's
# own name, the RetroArch pad profile to stage, the one-time mixer state.
oakmoss_resolve_event_paths() {
    log_message "Missing oakmoss_resolve_event_paths function"
}

stage_ra_autoconfig() {
    log_message "Missing stage_ra_autoconfig function"
}

oakmoss_init_audio() {
    log_message "Missing oakmoss_init_audio function"
}

# The onboard radio differs per board and neither driver may autoload: Zero 28
# 8189es, Zero 40 XR829. Each cfg names its module; kmsg is streamed to the card.
OAKMOSS_RADIO_KMSG=/mnt/SDCARD/Saves/spruce/radio-kmsg.log

oakmoss_load_onboard_radio() {
    [ -n "$WIFI_ONBOARD_MODULE" ] || return 0
    if usb_wifi_module_loaded "$WIFI_ONBOARD_MODULE"; then
        return 0
    fi
    # Every driver any board in this family ships, dependents before their base: one of
    # these probing the SDIO bus first is what knocked the real radio off it.
    for _other in 8189es xradio_wlan xradio_core xradio_mac xr829 xradio_btlpm \
                  aic8800_fdrv aic8800_btlpm aic8800_bsp sprdwl_ng sprdbt_tty uwe5622_bsp_sdio; do
        [ "$_other" = "$WIFI_ONBOARD_MODULE" ] && continue
        usb_wifi_module_loaded "$_other" && rmmod "$_other" 2>/dev/null
    done
    mkdir -p "$(dirname "$OAKMOSS_RADIO_KMSG")" 2>/dev/null
    cat /dev/kmsg > "$OAKMOSS_RADIO_KMSG" 2>/dev/null &
    _kmsg_pid=$!
    if [ -n "$OAKMOSS_RADIO_MODULES_DIR" ] && [ -f "$OAKMOSS_RADIO_MODULES_DIR/$WIFI_ONBOARD_MODULE.ko" ]; then
        # Card-carried modules, for a board not running the kernel ours were built against.
        # No board in the family needs this now; the order below is the XR829 stack's.
        rc=0
        for _m in xradio_mac xradio_core "$WIFI_ONBOARD_MODULE"; do
            [ -f "$OAKMOSS_RADIO_MODULES_DIR/$_m.ko" ] || continue
            usb_wifi_module_loaded "$_m" && continue
            insmod "$OAKMOSS_RADIO_MODULES_DIR/$_m.ko" 2>/tmp/oakmoss_radio_err || { rc=$?; break; }
        done
        _src="card:$OAKMOSS_RADIO_MODULES_DIR"
    else
        modprobe "$WIFI_ONBOARD_MODULE" 2>/tmp/oakmoss_radio_err; rc=$?
        _src="modprobe"
    fi
    for _ in 1 2 3 4 5; do
        [ -d /sys/class/net/wlan0 ] && break
        sleep 1
    done
    kill "$_kmsg_pid" 2>/dev/null
    sync
    log_message "oakMOSS radio: $_src $WIFI_ONBOARD_MODULE rc=$rc $(head -1 /tmp/oakmoss_radio_err 2>/dev/null); wlan0=$([ -d /sys/class/net/wlan0 ] && echo yes || echo no); sdio=$(ls /sys/bus/sdio/devices 2>/dev/null | tr '\n' ' '); $(grep -a -i 'xradio\|sbus\|RTW: \|8189\|firmware\|sdd\|Unable to handle\|BUG' "$OAKMOSS_RADIO_KMSG" 2>/dev/null | head -8 | cut -c1-160 | tr '\n' '|')"
    return 0
}

# Touch. The touch drivers ship in the base as modules nothing autoloads (oakMOSS
# sdk-patches/tree/090: XU20 hynitron, Zero 40 axs15205): built in, the XU20's probe
# ran on the kernel's init thread and stalled 6 of 8 boots before init (initcall
# marker, 2026-09-18). The cfg names the module (OAKMOSS_TOUCH_MODULE). Like the
# onboard radio it is loaded here, once the board has settled - in the background,
# with a bounded wait for its input node, so a probe that hangs costs touch for this
# session instead of the boot. The kernel log around the load goes to the card.
OAKMOSS_TOUCH_KMSG=/mnt/SDCARD/Saves/spruce/touch-kmsg.log

oakmoss_load_touch() {
    [ -n "$OAKMOSS_TOUCH_MODULE" ] || return 0
    usb_wifi_module_loaded "$OAKMOSS_TOUCH_MODULE" && return 0
    mkdir -p "$(dirname "$OAKMOSS_TOUCH_KMSG")" 2>/dev/null
    cat /dev/kmsg > "$OAKMOSS_TOUCH_KMSG" 2>/dev/null &
    _kmsg_pid=$!
    _kmsg_from=$(dmesg 2>/dev/null | wc -l)
    modprobe "$OAKMOSS_TOUCH_MODULE" 2>/tmp/oakmoss_touch_err &
    _mp_pid=$!
    _node=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        _node=$(oakmoss_find_event_by_name "*hyn*" "*cst*" "*axs*") && break
        sleep 0.5
    done
    if kill -0 "$_mp_pid" 2>/dev/null; then
        _st="modprobe still running after 5 s"
    else
        wait "$_mp_pid"
        _st="rc=$?"
    fi
    kill "$_kmsg_pid" 2>/dev/null
    sync
    log_message "oakMOSS touch: $OAKMOSS_TOUCH_MODULE $_st; node=${_node:-none}; $(head -1 /tmp/oakmoss_touch_err 2>/dev/null) $(dmesg 2>/dev/null | tail -n +$((_kmsg_from + 1)) | grep -a -e hyn -e axs -e 'xfer timeout' -e 'Unable to handle' -e 'BUG:' | head -6 | cut -c1-160 | tr '\n' '|')"
    return 0
}

# The oakMOSS base's init under its own name, so a board file that defines its own device_init
# can still run it.
device_init() {
    oakmoss_device_init
}

oakmoss_device_init() {
    oakmoss_runtime_mounts
    oakmoss_disown_base_supplicant
    oakmoss_seed_system_json

    export LD_LIBRARY_PATH="/usr/magicx/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"
    oakmoss_libs_paths
    # Done before the frontend or a game resumed at boot starts (PyUI applies none of these).
    oakmoss_restore_display &
    DEVICE_INIT_WAIT_PIDS="$DEVICE_INIT_WAIT_PIDS $!"

    oakmoss_chip_init
    oakmoss_load_touch
    oakmoss_resolve_event_paths
    oakmoss_load_onboard_radio

    (
        syslogd -S
        hwclock -s -u
    ) &
    # Bluetooth to the saved setting; a board without a radio returns at once.
    # Double-forked: runtime.sh waits for device_init's children.
    ( ( /mnt/SDCARD/spruce/scripts/bluetooth.sh boot ) & ) </dev/null >/dev/null 2>&1
    oakmoss_init_audio
    stage_ra_autoconfig

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash 2>/dev/null
        chmod +x /bin/bash 2>/dev/null
    fi
}

# Sleep is faux sleep, MinUI/Moss's model (none of their boards uses kernel suspend):
# suspend-to-RAM never came back on the MagicX stock boot chain (XU20 2026-09-18: after
# `echo mem` neither the power key nor the +300 s RTC alarm woke it, and no driver's
# resume ran). The panel goes dark and the session stops until sleep_helper's pseudo loop
# sees the power button, or its idle timer powers the board off. The radio stays up.
#
# Real suspend-to-RAM where the board has been proven to resume (OAKMOSS_REAL_SLEEP=1 in its
# cfg): the Zero 28 on the SDK's firmware and the Zero 40 on MagicX's both came back from
# `mem` on the RTC alarm (2026-09-24). The XU20 too, with its devices suspending one at a
# time (OAKMOSS_PM_ASYNC=0 in its cfg): async suspend never finished there (2026-09-28).
device_uses_pseudo_sleep() {
    if [ "$OAKMOSS_REAL_SLEEP" = "1" ]; then echo "false"; else echo "true"; fi
}

# No oakMOSS board reads a lid yet; sleep_helper's pseudo loop takes the power button only
# while this reads "1".
device_lid_open() {
    echo "1"
}

# PyUI's SDL2 directory. The base's SDL2_image (2.0.3) predates QOI, so box art converted
# by "Optimize boxart" would not load. PySDL2 takes a single directory: link the base's
# SDL2 libraries (DEVICE_PYSDL2_DLL_PATH) next to PyUI's QOI-capable SDL2_image in tmpfs,
# as the Brick pairs them in spruce/brick/sdl2. Prints the directory.
oakmoss_pyui_sdl_dir() {
    _dir=/tmp/pyui-sdl2
    mkdir -p "$_dir"
    rm -f "${_dir:?}"/*
    for _lib in "${DEVICE_PYSDL2_DLL_PATH:-/usr/magicx/lib}"/libSDL2*; do
        case "$_lib" in
            */libSDL2_image*) ;;
            *) ln -s "$_lib" "$_dir/" ;;
        esac
    done
    ln -s /mnt/SDCARD/App/PyUI/dll/libSDL2_image-2.0.so "$_dir/"
    echo "$_dir"
}

# Level 1..10 -> raw panel value on oakMOSS. The curve is PyUI's own (DeviceCommon.
# map_backlight_from_10_to_full_255: 25 a step, 255 at 10), the one the MagicX panels were
# tested on; a133p.sh's (level-1)*254/9+1 stays with the stock TrimUI boards. Mirrored where the
# backlight PWM is inverted (OAKMOSS_BACKLIGHT_REVERSED: the XU20 and the Zero 40).
oakmoss_backlight_raw() {
    val="$1"
    case "$val" in ''|*[!0-9]*) val=1 ;; esac
    [ "$val" -lt 1 ] && val=1
    [ "$val" -gt 10 ] && val=10
    if [ "$val" -eq 10 ]; then raw=255; else raw=$((val * 25)); fi
    [ "$OAKMOSS_BACKLIGHT_REVERSED" = "1" ] && raw=$((256 - raw))
    echo "$raw"
}

# The saved backlight and display levels at boot, through the hooks PyUI's commands use and in
# its old startup order. A level missing from the json ("null") leaves the panel as it is.
oakmoss_restore_display() {
    # shellcheck disable=SC2046 # the five levels, one word each
    set -- $(jq -r '.backlight, .contrast, .saturation, .brightness, .hue' "$SYSTEM_JSON" 2>/dev/null)
    [ $# -eq 5 ] || return 0
    case "$1" in ''|*[!0-9]*) ;; *) apply_backlight "$1" ;; esac
    shift
    for _setting in contrast saturation brightness hue; do
        case "$1" in ''|*[!0-9]*) ;; *) "apply_display_$_setting" "$1" ;; esac
        shift
    done
}

# PyUI's About line: the oakMOSS release (a build past a tag shows as v0.5.0-beta.2+43), else
# the Tina config the base was built from, never another board's name.
device_get_fw_version() {
    _version=$(cat /usr/magicx/version 2>/dev/null)
    if [ -n "$_version" ]; then
        echo "oakMOSS $(echo "$_version" | sed -E 's/^(v?[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?)-([0-9]+)-g[0-9a-f]+$/\1+\3/')"
    else
        _model=$(cat /usr/magicx/device 2>/dev/null)
        echo "magicx-tina (${_model:-${PLATFORM:-unknown}})"
    fi
}

# The brightness keys (buttons_watchdog -> device_backlight_up/down): the panel, then the level
# saved. Overrides a133p.sh's set_backlight (sourced above).
set_backlight() {
    val="$1"
    case "$val" in ''|*[!0-9]*) return 1 ;; esac
    [ "$val" -lt 1 ] && val=1
    [ "$val" -gt 10 ] && val=10
    apply_backlight "$val"
    tmp="${SYSTEM_JSON}.tmp.$$"
    jq ".backlight = $val" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
}

# The in-game menu composes over a framebuffer snapshot; the panel is portrait and
# the UI rotated, so the capture is un-rotated the way the XX line does it.
take_screenshot() {
    screenshot_path="$1"
    /mnt/SDCARD/spruce/bin64/fbscreenshot "$screenshot_path" -r "${DISPLAY_ROTATION:-0}"
}

set_volume() {
    new_vol="${1:-0}"
    SAVE_TO_CONFIG="${2:-true}"
    [ "$new_vol" -lt 0 ] 2>/dev/null && new_vol=0
    [ "$new_vol" -gt 20 ] 2>/dev/null && new_vol=20
    oakmoss_apply_volume "$new_vol"
    bt_headset_volume "$new_vol"
    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol // 0' "$SYSTEM_JSON" 2>/dev/null)
        [ "$current_volume" = "$new_vol" ] || save_volume_to_config_file "$new_vol"
    fi
}

# No RGB LED on these boards (no /sys/class/led_anim): quiet no-ops in place of
# device.sh's "Missing ..." log lines.
enable_or_disable_rgb() {
    log_message "enable_or_disable_rgb: no RGB LED on $PLATFORM" -v
}

rgb_led() {
    log_message "rgb_led: no RGB LED on $PLATFORM" -v
}

# PyUI copies its bundled default into the system json on its first start, but
# runtime.sh reads that file before PyUI runs, so seed it here as Flip.sh does.
oakmoss_seed_system_json() {
    json="$(get_config_path 2>/dev/null)"
    [ -n "$json" ] && [ ! -f "$json" ] || return 0
    cp /mnt/SDCARD/App/PyUI/main-ui/devices/oakmoss/oakmoss-system.json "$json" 2>/dev/null \
        && log_message "oakMOSS: seeded $json from the bundled default"
}
