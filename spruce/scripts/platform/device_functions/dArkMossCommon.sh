#!/bin/sh
# Shared device functions for every platform hosted by dArkMoss
# (github.com/spruceUI/dArkMoss): Debian trixie, systemd, NetworkManager.
# The platform file sources this and adds only what its hardware needs.
#
#   - nmcli owns association and DHCP, so the DHCP hooks are deliberately empty.
#   - TF2 is mounted at /mnt/SDCARD by the base and unmounted by systemd on the
#     way down; spruce must not fight it.
#   - display (bin64/display_text.elf) cannot open a window on this Mali blob,
#     which only offers GLES configs. legacy_display is sourced for display_kill.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

DARKMOSS_DEBUG_LOG="/mnt/SDCARD/Saves/spruce/darkmoss_debug.log"

device_init() {
    migrate_platform_files
    resolve_pad_node
    log_message "$PLATFORM: TF2 is ${SD_DEV:-<unresolved>} at $SD_MOUNTPOINT"
    resolve_key_event_node
    setup_mainui_alias
    set_backlight "$(get_backlight_level)"
    darkmoss_wifi_up
    device_bluetooth_supported && /mnt/SDCARD/spruce/scripts/bluetooth.sh boot &
    darkmoss_debug_dump
    clear_stale_pmic_power_en &
}

new_execution_loop() {
    log_message "new_execution_loop unneeded on this device" -v
}

# Debian's sshd owns port 22; anything but "dropbearmulti" sends the SSH toggle
# down its systemctl branch. The unit is "ssh", not "sshd". The spruce login is
# baked into the image by setup_spruce_handoff-rk3566.sh.
get_ssh_service_name() {
    echo "ssh"
}

  #################
#####   INPUT   #####
  #################

# The pad, by by-path link first (PAD_NODE_CANDIDATES) then by evdev name
# (PAD_NAME_CANDIDATES), both from the platform cfg.
resolve_pad_node() {
    _pad=""
    for _node in $PAD_NODE_CANDIDATES; do
        [ -e "$_node" ] && { _pad="$_node"; break; }
    done
    if [ -z "$_pad" ]; then
        _old_ifs="$IFS"; IFS='|'
        for _name in $PAD_NAME_CANDIDATES; do
            for _dir in /sys/class/input/event*; do
                if [ "$(cat "$_dir/device/name" 2>/dev/null)" = "$_name" ]; then
                    _pad="/dev/input/$(basename "$_dir")"
                    break 2
                fi
            done
        done
        IFS="$_old_ifs"
    fi
    if [ -n "$_pad" ]; then
        export EVENT_PATH_READ_INPUTS_SPRUCE="$_pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$_pad"
        export EVENT_PATH_SEND_TO_DRASTIC="$_pad"
        log_message "$PLATFORM: joypad at $_pad"
    else
        log_message "$PLATFORM: no joypad node found - controls will be dead"
    fi
}

# Does the node declare BOTH KEY_VOLUMEDOWN(114) and KEY_VOLUMEUP(115)? A
# phantom single capability exists on some adc-keys nodes; a real rocker has both.
node_reports_volume_keys() {
    _caps="/sys/class/input/$1/device/capabilities/key"
    [ -r "$_caps" ] || return 1
    awk '{
        s=""
        for (i=1; i<=NF; i++) { w=$i; if (i>1) { while (length(w)<16) w="0" w } s=s w }
        have=0
        for (k=114; k<=115; k++) {
            nib=int(k/4); bit=k%4; pos=length(s)-nib
            if (pos < 1) continue
            c=tolower(substr(s,pos,1))
            v=index("0123456789abcdef",c)-1
            if (v < 0) continue
            if (int(v/(2^bit))%2 == 1) have++
        }
        exit (have==2)?0:1
    }' "$_caps"
}

# Find the power and volume nodes by asking the kernel, and persist them to
# SPRUCE_INPUT_NODES_FILE: the button watchdogs are separate processes that
# re-source the platform cfg, which reads that file back.
#
# When the volume keys sit on the pad itself, every pad watcher already sees
# them; EVENT_PATH_VOLUME is parked on the power node so nothing reads the pad
# twice, and VOLUME_KEYS_ON_PAD tells buttons_watchdog to leave volume to the
# menu while one is up.
resolve_key_event_node() {
    _power=""
    _volume=""
    _seen=""

    for _dir in /sys/class/input/event*; do
        [ -e "$_dir" ] || continue
        _ev=$(basename "$_dir")
        _name=$(cat "$_dir/device/name" 2>/dev/null)
        _seen="$_seen ${_ev}:${_name}"

        if node_reports_volume_keys "$_ev" && [ -z "$_volume" ]; then
            _volume="/dev/input/$_ev"
        fi
        case "$_name" in
            *pwrkey*|*Power*|*power*) [ -z "$_power" ] && _power="/dev/input/$_ev" ;;
        esac
    done

    log_message "$PLATFORM: input nodes:$_seen"

    if [ -n "$_power" ] && [ -c "$_power" ]; then
        export EVENT_PATH_POWER="$_power"
        log_message "$PLATFORM: power key on $_power"
    fi

    VOLUME_KEYS_ON_PAD=0
    if [ -n "$_volume" ] && [ -c "$_volume" ]; then
        if [ "$_volume" = "$EVENT_PATH_READ_INPUTS_SPRUCE" ]; then
            VOLUME_KEYS_ON_PAD=1
            export EVENT_PATH_VOLUME="$EVENT_PATH_POWER"
            log_message "$PLATFORM: volume keys are on the joypad node"
        else
            export EVENT_PATH_VOLUME="$_volume"
            log_message "$PLATFORM: volume keys on $_volume"
        fi
    else
        log_message "$PLATFORM: no node reports the volume keys - leaving $EVENT_PATH_VOLUME"
    fi
    export VOLUME_KEYS_ON_PAD

    {
        echo "EVENT_PATH_READ_INPUTS_SPRUCE='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_SEND_TO_RA_AND_PPSSPP='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_SEND_TO_DRASTIC='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_VOLUME='${EVENT_PATH_VOLUME}'"
        echo "EVENT_PATH_POWER='${EVENT_PATH_POWER}'"
        echo "VOLUME_KEYS_ON_PAD='${VOLUME_KEYS_ON_PAD}'"
    } > "$SPRUCE_INPUT_NODES_FILE" 2>/dev/null
}

setup_mainui_alias() {
    MAINUI="/mnt/SDCARD/spruce/flip/bin/MainUI"
    PY="/mnt/SDCARD/spruce/flip/bin/python3.10"

    if [ ! -f "$PY" ]; then
        log_message "$PLATFORM: $PY missing - PyUI cannot start"
        return 1
    fi

    if [ -s "$MAINUI" ] && [ "$(stat -c%s "$MAINUI" 2>/dev/null)" = "$(stat -c%s "$PY" 2>/dev/null)" ]; then
        return 0
    fi

    touch "$MAINUI" 2>/dev/null
    mount -o bind "$PY" "$MAINUI" 2>/dev/null

    if [ ! -s "$MAINUI" ]; then
        log_message "$PLATFORM: MainUI bind mount failed, copying interpreter instead"
        umount "$MAINUI" 2>/dev/null
        cp "$PY" "$MAINUI" || { log_message "$PLATFORM: could not create MainUI"; return 1; }
        chmod +x "$MAINUI" 2>/dev/null
    fi
    log_message "$PLATFORM: MainUI alias ready ($(stat -c%s "$MAINUI" 2>/dev/null) bytes)"
}

  ###################
#####   POWER   #####
  ###################

device_get_battery_percent() {
    cat "$BATTERY/capacity" 2>/dev/null || echo 0
}

# Read the charger, not battery/status, which is unreliable on these RK boards.
device_get_charging_status() {
    if [ "$(cat /sys/class/power_supply/ac/online 2>/dev/null)" = "1" ]; then
        if [ "$(cat "$BATTERY/capacity" 2>/dev/null)" = "100" ]; then
            echo "Full"
        else
            echo "Charging"
        fi
    else
        echo "Discharging"
    fi
}

device_headphones_connected() {
    are_headphones_plugged_in
}

  ####################
#####   FIRMWARE   #####
  ####################

# OS_VERSION is the release tag when CI cut one, else a build date. Only a
# tagged release is a version worth comparing; no stamp at all (images before
# it existed) or a date (an untagged build, or v1.0.7 whose build-all dropped
# the tag) is older than every tagged release and gets the update offered.
darkmoss_installed_version() {
    sed -n 's/^OS_VERSION="\{0,1\}[vV]\{0,1\}\([0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null
}

check_if_fw_needs_update() {
    [ -n "$TARGET_DARKMOSS_VERSION" ] || { echo "false"; return; }
    _have="$(darkmoss_installed_version)"
    if [ -z "$_have" ]; then
        echo "true"
        return
    fi
    _have_n="$(printf '%s' "$_have" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')"
    _want_n="$(printf '%s' "$TARGET_DARKMOSS_VERSION" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')"
    if [ "$_have_n" -lt "$_want_n" ] 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

  ###################
#####   SLEEP   #####
  ###################

WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

# The base has no hwclock (trixie moved it to util-linux-extra); the RTC
# publishes the same value in sysfs.
device_get_hw_epoch() {
    cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null
}

# Through systemd so the base's system-sleep hook runs: it saves and restores
# the backlight, mutes the speaker amp, and restores governors and LEDs. The
# call returns before the suspend, so wait for the sleep unit to finish.
trigger_device_sleep() {
    systemctl suspend >/dev/null 2>&1 || return 1
    sleep 2
    while systemctl is-active --quiet systemd-suspend.service; do
        sleep 0.5
    done
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

darkmoss_exit_sleep() {
    set_volume "$(get_volume_level)" false
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
}

device_exit_sleep() {
    darkmoss_exit_sleep
}

# extcon reports 1, a DRM connector reports "connected".
device_hdmi_connected() {
    case "$(cat "$HDMI_STATE_PATH" 2>/dev/null)" in
        1|connected) return 0 ;;
        *) return 1 ;;
    esac
}

  ###################
#####   NETWORK   #####
  ###################

device_manages_own_wifi() {
    return 0
}

device_wifi_power_on() {
    nmcli radio wifi on >/dev/null 2>&1
}

device_wifi_power_off() {
    nmcli radio wifi off >/dev/null 2>&1
}

device_start_dhcp_client() {
    return 0
}

device_stop_dhcp_client() {
    return 0
}

# nmcli's error output echoes the password back, so none of it is kept. The
# network is also saved to the card's wpa_supplicant.conf, where every other
# spruce device keeps it, so the password travels with the card and a fresh
# dArkMoss flash finds it again at boot (darkmoss_wifi_up).
device_wifi_connect() {
    command -v nmcli >/dev/null 2>&1 || return 1
    wpa_conf_save_network "$1" "$2"
    # NM 1.52 refuses "device wifi connect" when a profile for the SSID already exists
    nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r _uuid _type; do
        [ "$_type" = "802-11-wireless" ] || continue
        [ "$(nmcli -g 802-11-wireless.ssid connection show uuid "$_uuid" 2>/dev/null)" = "$1" ] || continue
        nmcli connection delete uuid "$_uuid" >/dev/null 2>&1
    done
    if [ -n "$2" ]; then
        nmcli -w 45 device wifi connect "$1" password "$2" >/dev/null 2>&1
    else
        nmcli -w 45 device wifi connect "$1" >/dev/null 2>&1
    fi
}

  #################
#####   AUDIO   #####
  #################

are_headphones_plugged_in() {
    [ -n "$HEADPHONE_STATE_PATH" ] && [ "$(cat "$HEADPHONE_STATE_PATH" 2>/dev/null)" = "1" ]
}

apply_playback_path() {
    if are_headphones_plugged_in; then
        amixer -q cset name="$AUDIO_PATH_CONTROL" "$AUDIO_PATH_HP" 2>/dev/null
    else
        amixer -q cset name="$AUDIO_PATH_CONTROL" "$AUDIO_PATH_SPK" 2>/dev/null
    fi
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON" 2>/dev/null || echo 0
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -lt 20 ]; then
        set_volume "$(( VOLUME_LV + 1 ))"
    fi
}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -gt 0 ]; then
        set_volume "$(( VOLUME_LV - 1 ))"
    fi
}

get_current_volume() {
    amixer get 'Master' 2>/dev/null | sed -n 's/.*\[\([0-9]\+\)%\].*/\1/p' | head -1
}

# Level before path: switching output with the old level applied is what
# produced the burst the Flip had to be fixed for.
set_volume() {
    VOLUME_LV="$1"
    SAVE_TO_CONFIG="${2:-true}"

    VOLUME_PCT=$(( VOLUME_LV * 5 ))
    [ "$VOLUME_PCT" -gt 100 ] && VOLUME_PCT=100
    [ "$VOLUME_PCT" -lt 0 ] && VOLUME_PCT=0

    amixer -q sset -M 'Master' "${VOLUME_PCT}%" 2>/dev/null
    bt_headset_volume "$(( VOLUME_PCT / 5 ))"
    apply_playback_path
    log_message "$PLATFORM: volume ${VOLUME_LV}/20 (${VOLUME_PCT}%)"

    if [ "$SAVE_TO_CONFIG" = true ]; then
        save_volume_to_config_file "$VOLUME_LV" 2>/dev/null
    fi
}

# systemd owns both daemons (shipped disabled); a runtime drop-in adds --keep-alive,
# so the gap between PyUI and a game keeps the headset's stream running.
BLUEALSA_KEEP_ALIVE=10
device_bluetooth_up() {
    _dropin=/run/systemd/system/bluealsa.service.d/spruce-keep-alive.conf
    if [ ! -f "$_dropin" ]; then
        _cmd=$(systemctl show -p ExecStart --value bluealsa 2>/dev/null | sed -n 's/.*argv\[\]=\([^;]*\);.*/\1/p' | head -n 1)
        case "$_cmd" in
            ""|*--keep-alive*) ;;
            *)
                mkdir -p "${_dropin%/*}"
                printf '[Service]\nExecStart=\nExecStart=%s --keep-alive=%s\n' "${_cmd% }" "$BLUEALSA_KEEP_ALIVE" > "$_dropin"
                systemctl daemon-reload
                systemctl is-active --quiet bluealsa && systemctl restart bluealsa
                ;;
        esac
    fi
    systemctl start bluetooth bluealsa
}

device_bluetooth_down() {
    systemctl stop bluealsa bluetooth
}

# bluealsad 5's ALSA plugin would switch the codec to each client's rate (see
# asound-setup.sh); 48 kHz is what it picks at connect and what games use.
BT_PCM_RATE=48000

# bluealsad 5 has bluealsactl: soft volume, so the level holds on headsets that
# ignore the remote one. Same 0-20 level as device.sh's default.
bt_headset_volume() {
    pgrep -x bluealsad >/dev/null 2>&1 || return 0
    _v=$(( $1 * 127 / 20 ))
    for _pcm in $(${BTCTL_TIMEOUT:-timeout 2} bluealsactl --quiet list-pcms 2>/dev/null | grep '/a2dpsrc/sink$'); do
        # bluealsad 5.0 starts each headset on its own volume, and turning SoftVolume on
        # resets the level to full: only switch it when off, or every press bursts.
        ${BTCTL_TIMEOUT:-timeout 2} bluealsactl soft-volume "$_pcm" 2>/dev/null | grep -q true ||
            ${BTCTL_TIMEOUT:-timeout 2} bluealsactl soft-volume "$_pcm" y >/dev/null 2>&1
        ${BTCTL_TIMEOUT:-timeout 2} bluealsactl volume "$_pcm" "$_v" "$_v" >/dev/null 2>&1
    done
}

get_backlight_level() {
    jq -r '.backlight // 5' "$SYSTEM_JSON" 2>/dev/null || echo 5
}

set_backlight() {
    level="$1"
    [ "$level" -lt 0 ] && level=0
    [ "$level" -gt 10 ] && level=10
    eval "raw=\$SYSTEM_BRIGHTNESS_$level"
    echo "$raw" > "$DEVICE_BRIGHTNESS_PATH"
    echo 0 > /sys/class/backlight/backlight/bl_power 2>/dev/null
    log_message "$PLATFORM: backlight ${level}/10 (raw $raw)"
    tmp="$SYSTEM_JSON.tmp.$$"
    jq ".backlight = $level" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
}

brightness_down() {
    set_backlight $(( $(get_backlight_level) - 1 ))
}

brightness_up() {
    set_backlight $(( $(get_backlight_level) + 1 ))
}

# The base keeps its ALSA config in ~/.asoundrc (/etc/asound.conf is empty), so a
# program with another HOME would get raw hw:0,0. This is that file, its default
# renamed spruce_speaker; asound-setup.sh adds spruce_bt and the default.
ASOUND_SPRUCE_PCMS=1
device_write_default_asound_rc() {
    cat > "$ASOUND_CONF" <<ASOUND
pcm.spruce_speaker {
    type        plug
    slave.pcm   "softvol"
}

ctl.!default {
    type        hw
    card        0
}

pcm.ddmix {
    ipc_key     1024
    type        dmix
    slave {
        pcm         "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 4096
        rate        44100
    }
}

pcm.softvol {
    type        softvol
    slave {
        pcm     "ddmix"
    }
    control {
        name    "Master"
        card    0
    }
}
ASOUND
}

  #############################
#####   MENU LOOP HOOKS   #####
  #############################

# Full clock for SDL2 startup, then back to smart once the menu is up. Not the
# Flip's version, which also pins the memory controller and never releases it.
prepare_for_pyui_launch() {
    set_performance
    (
        sleep 5
        if flag_check "in_menu"; then
            set_smart
        fi
        unlock_governor 2>/dev/null
    ) &
}

post_pyui_exit() {
    log_message "post_pyui_exit not needed on this device" -v
}

enable_or_disable_rgb() {
    log_message "No controllable RGB LED on this device" -v
}

rgb_led() {
    return 0
}

  ###############################
#####   EMULATION AND PORTS   #####
  ###############################

# 64-bit only. The per-core library cases are the Flip's and apply unchanged:
# same RK3566, same aarch64 userland. EASYRPG genuinely has no lib-RGB30.
setup_for_retroarch() {
    case "$CORE" in
        uae4arm)      export LD_LIBRARY_PATH="$EMU_DIR:$LD_LIBRARY_PATH" ;;
        easyrpg)      export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip" ;;
        yabasanshiro) export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib64" ;;
    esac

    case "$RA_BIN" in
        ra32.*)
            export CORE_DIR="$RA_DIR/.retroarch/cores"
            export GLIBC_TUNABLES=glibc.rtld.execstack=2
            ;;
        *)      export CORE_DIR="$RA_DIR/.retroarch/cores64" ;;
    esac

    if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
        export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
    else
        export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
    fi

    echo "$RA_BIN"
}

device_prepare_for_ports_run() {
    :
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run unneeded on this device" -v
}

# Force-feedback rumble through the pad's evdev node. On a unit without a
# motor the kernel accepts the effect and nothing happens.
# Tiers tuned 2026-09-01 on a modded RGB30: the small button motor is faint,
# so the tier carries a duration as well as a magnitude.
darkmoss_vibrate() {
    duration=""
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    case "$intensity" in
        "Off")    return 0 ;;
        "Weak")   intensity=0xC000; tier_duration=200 ;;
        "Medium") intensity=0xFFFF; tier_duration=300 ;;
        "Strong") intensity=0xFFFF; tier_duration=450 ;;
        *)        intensity=0xFFFF; tier_duration=300 ;;
    esac
    [ -n "$duration" ] || duration="$tier_duration"

    [ -x /mnt/SDCARD/spruce/bin64/rumble ] || return 0
    /mnt/SDCARD/spruce/bin64/rumble "$EVENT_PATH_READ_INPUTS_SPRUCE" "$intensity" "$duration"
}

vibrate() {
    darkmoss_vibrate "$@"
}

# fb0 is a dead shim under DRM, so grab the KMS plane. spruce/bin/ffmpeg is the
# static build with the kmsgrab demuxer (bin64/ffmpeg has none) and starts in
# 76ms against Debian's 2.3s; Debian's stays as the fallback.
take_screenshot() {
    screenshot_path="$1"
    [ -n "$screenshot_path" ] || return 1
    _ff=""
    for _c in /mnt/SDCARD/spruce/bin/ffmpeg /usr/bin/ffmpeg; do
        [ -x "$_c" ] && { _ff="$_c"; break; }
    done
    [ -n "$_ff" ] || {
        log_message "take_screenshot: no ffmpeg with kmsgrab available"
        return 1
    }
    mkdir -p "$(dirname "$screenshot_path")" 2>/dev/null

    if timeout 15 "$_ff" -hide_banner -loglevel error \
        -f kmsgrab -i - \
        -vf "hwdownload,format=bgr0,format=rgba" \
        -frames:v 1 -update 1 -y "$screenshot_path" >/dev/null 2>&1; then
        return 0
    fi

    rm -f "$screenshot_path" 2>/dev/null
    log_message "take_screenshot: kmsgrab capture failed"
    return 1
}

get_config_path() {
    echo "$SYSTEM_JSON"
}

# Values from a live RGB30's retroarch.cfg on the udev driver, which numbers
# this pad the same way on every dArkMoss unit; hotkey is SELECT (8). The
# entries shipped as "nul" are reset to "nul" too.
set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"8\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"4\"" \
        "input_save_state_btn = \"5\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"10\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}

# spruce's bundled netcat needs an ELF loader path this base lacks; Debian's
# nc.openbsd at /usr/bin/nc does the job.
send_menu_button_to_retroarch() {
    if pgrep -f "ra64.universal|ra32.universal|retroarch" >/dev/null; then
        echo "MENU_TOGGLE" | /usr/bin/nc -u -w1 127.0.0.1 55355
    fi
}

  ####################
#####   SHUTDOWN   #####
  ####################

device_system_handles_sdcard_unmount() {
    return 0
}

device_needs_strict_unmount() {
    return 1
}

device_run_reboot_cmd() {
    systemctl reboot
}

# Through systemd like reboot, so /mnt/SDCARD is unmounted cleanly.
run_poweroff_cmd() {
    systemctl poweroff
}

# save_poweroff.sh kills runtime.sh, which is spruce-launch.service's MainPID.
# The unit holds tty1 with TTYVHangup=yes, so stopping it SIGHUPs everything
# still on that terminal, the shutdown script included. SIG_IGN survives exec,
# so this covers stage 2 too.
darkmoss_prepare_for_poweroff() {
    trap "" HUP
    sync
}

device_prepare_for_poweroff() {
    darkmoss_prepare_for_poweroff
}

  #####################
#####   BRING-UP   #####
  #####################

darkmoss_drm_holders() {
    for _fd in /proc/[0-9]*/fd/*; do
        _tgt="$(readlink "$_fd" 2>/dev/null)" || continue
        case "$_tgt" in
            /dev/dri/*)
                _pid="${_fd#/proc/}"
                _pid="${_pid%%/*}"
                _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
                [ -z "$_cmd" ] && _cmd="[$(cat "/proc/$_pid/comm" 2>/dev/null)]"
                echo "  pid $_pid ($_cmd) -> $_tgt"
                ;;
        esac
    done
}

# A device that used to run as another platform (the RGB20SX ran as RGB30)
# keeps what it saved under the old name.
migrate_platform_files() {
    [ -n "$PLATFORM_MIGRATE_FROM" ] || return 0
    _old="$PLATFORM_MIGRATE_FROM"
    _old_lc="$(echo "$_old" | tr 'A-Z' 'a-z')"
    _ppsspp="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
    for _pair in \
        "/mnt/SDCARD/App/PyUI/config/${_old_lc}-system.json|$SYSTEM_JSON" \
        "/mnt/SDCARD/Saves/ra-configs/retroarch-$_old.cfg|/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg" \
        "$_ppsspp/ppsspp-$_old.ini|$_ppsspp/ppsspp-$PLATFORM.ini" \
        "$_ppsspp/controls-$_old.ini|$_ppsspp/controls-$PLATFORM.ini" \
        "/mnt/SDCARD/Saves/saves/advmame/$_old|/mnt/SDCARD/Saves/saves/advmame/$PLATFORM"; do
        _src="${_pair%%|*}"
        _dst="${_pair#*|}"
        if [ -e "$_src" ] && [ ! -e "$_dst" ]; then
            cp -a "$_src" "$_dst" && log_message "$PLATFORM: carried over $_src"
        fi
    done
}

# Mainline (ROCKNIX) leaves fuel gauge data in RK817 0x99/0xa4; the BSP kernel
# restores regulator enables from them at poweroff, which reboots the device.
clear_stale_pmic_power_en() {
    "$DEVICE_PYTHON3_PATH" - <<'EOF' | while read -r line; do log_message "$line"; done
import fcntl, os
fd = os.open("/dev/i2c-0", os.O_RDWR)
fcntl.ioctl(fd, 0x0706, 0x20)
for reg in (0x99, 0xa4):
    os.write(fd, bytes([reg]))
    value = os.read(fd, 1)[0]
    if value:
        os.write(fd, bytes([reg, 0]))
        print(f"RK817: cleared stale 0x{reg:02x} (was 0x{value:02x})")
EOF
}

# A snapshot of the machine on every boot, for reading off the card.
darkmoss_debug_dump() {
    {
        echo "================ $(date 2>/dev/null) ================"
        echo "--- platform $PLATFORM"
        echo "--- kernel cmdline"
        cat /proc/cmdline 2>&1
        echo "--- device tree model"
        tr -d '\0' < /sys/firmware/devicetree/base/model 2>&1; echo
        echo "--- os-release"
        grep -E "^(OS_NAME|OS_VERSION|HW_DEVICE|PRETTY_NAME)=" /etc/os-release 2>&1
        echo "--- block devices"
        lsblk -o NAME,SIZE,LABEL,MOUNTPOINT 2>&1
        echo "--- /dev/dri"
        ls -l /dev/dri/ 2>&1
        echo "--- drm connectors"
        for _s in /sys/class/drm/*/status; do
            [ -r "$_s" ] && echo "  $_s = $(cat "$_s" 2>/dev/null)"
        done
        echo "--- who holds /dev/dri"
        _h="$(darkmoss_drm_holders)"
        [ -n "$_h" ] && echo "$_h" || echo "  (nobody)"
        echo "--- input devices"
        for _dir in /sys/class/input/event*; do
            echo "  $(basename "$_dir"): $(cat "$_dir/device/name" 2>/dev/null) key=$(cat "$_dir/device/capabilities/key" 2>/dev/null) abs=$(cat "$_dir/device/capabilities/abs" 2>/dev/null) ff=$(cat "$_dir/device/capabilities/ff" 2>/dev/null)"
        done
        ls -l /dev/input/by-path/ 2>&1
        for _dir in /sys/class/input/event*; do
            echo "  $(basename "$_dir") sw=$(cat "$_dir/device/capabilities/sw" 2>/dev/null)"
        done
        echo "--- extcon"
        for _x in /sys/class/extcon/*; do
            echo "  $_x name=$(cat "$_x/name" 2>/dev/null) state=$(cat "$_x/state" 2>/dev/null | tr '\n' ' ')"
        done
        echo "--- leds"
        for _l in /sys/class/leds/*; do
            echo "  $_l: $(ls "$_l" 2>/dev/null | tr '\n' ' ')"
        done
        echo "--- resolved: pad=$EVENT_PATH_READ_INPUTS_SPRUCE power=$EVENT_PATH_POWER volume=$EVENT_PATH_VOLUME on_pad=$VOLUME_KEYS_ON_PAD"
        echo "--- sound cards and controls"
        cat /proc/asound/cards 2>&1
        amixer controls 2>&1 | head -40
        echo "--- backlight"
        for _b in /sys/class/backlight/*; do
            echo "  $_b max=$(cat "$_b/max_brightness" 2>/dev/null) now=$(cat "$_b/brightness" 2>/dev/null)"
        done
        echo "--- power supplies"
        for _p in /sys/class/power_supply/*; do
            echo "  $_p type=$(cat "$_p/type" 2>/dev/null) online=$(cat "$_p/online" 2>/dev/null) status=$(cat "$_p/status" 2>/dev/null) capacity=$(cat "$_p/capacity" 2>/dev/null)"
        done
        echo "--- pwm / leds / extcon / rkwifi"
        ls /sys/class/pwm/ /sys/class/leds/ /sys/class/extcon/ /sys/class/rkwifi/ 2>&1
        echo "--- gpu devfreq steps"
        cat "$GPU_GOVENOR_DIR/available_frequencies" 2>&1
        echo "--- wifi / bt modules"
        lsmod 2>/dev/null | grep -iE "8723|8821|rtl|rtw|bcm|wlan|btusb|hci" || echo "  no wifi/bt module loaded"
        ip link show 2>&1 | grep -E "^[0-9]+:" 
        echo "--- failed units"
        command -v systemctl >/dev/null 2>&1 && systemctl list-units --failed --no-pager --no-legend 2>&1 | head -20
        echo "--- mounts"
        mount 2>&1 | grep -E "SDCARD|mmcblk"
        echo "--- network (NetworkManager)"
        ip -4 -o addr show 2>&1 | grep -v " lo " || echo "  no IPv4 address"
        if command -v nmcli >/dev/null 2>&1; then
            echo "  nmcli state: $(nmcli -t -f STATE general 2>&1)"
            echo "  active: $(nmcli -t -f NAME,DEVICE connection show --active 2>&1 | tr '\n' ' ')"
        fi
        echo "--- listening on 22"
        ss -ltn 2>/dev/null | grep -E ":22[[:space:]]" || echo "  nothing on 22 yet"
    } >> "$DARKMOSS_DEBUG_LOG" 2>&1
}

# Force the base sshd up regardless of the Network Settings toggle, for bring-up
# when the settings screen cannot be reached:
#     touch /mnt/SDCARD/spruce/flags/darkmoss_force_ssh
# Started, not enabled, so the image is left as it was.
darkmoss_ssh_up() {
    [ -e /mnt/SDCARD/spruce/flags/darkmoss_force_ssh ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0

    if systemctl is-active --quiet "$(get_ssh_service_name)" 2>/dev/null; then
        log_message "$PLATFORM: base sshd already running"
        return 0
    fi
    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -A >/dev/null 2>&1
    fi
    if systemctl start "$(get_ssh_service_name)" >/dev/null 2>&1; then
        log_message "$PLATFORM: started base sshd"
    else
        log_message "$PLATFORM: could not start $(get_ssh_service_name)"
    fi
}

# Give NetworkManager every network the card knows. NetworkManager's own
# profiles live on TF1, so a reflash or a new dArkMoss device starts with none;
# the card's wpa_supplicant.conf is where the rest of the fleet keeps them.
# Profiles are named after the SSID, as "nmcli device wifi connect" names them.
# The password goes to nmcli as an argument, never through the log.
darkmoss_import_card_networks() {
    command -v nmcli >/dev/null 2>&1 || return 0
    _known="$(nmcli -t -f NAME connection show 2>/dev/null | sed 's/\\:/:/g')"
    wpa_conf_list_networks | while IFS="$(printf '\t')" read -r _ssid _psk; do
        [ -n "$_ssid" ] || continue
        printf '%s\n' "$_known" | grep -qxF "$_ssid" && continue
        if [ -n "$_psk" ]; then
            nmcli connection add type wifi ifname wlan0 con-name "$_ssid" ssid "$_ssid" \
                wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$_psk" >/dev/null 2>&1
        else
            nmcli connection add type wifi ifname wlan0 con-name "$_ssid" ssid "$_ssid" >/dev/null 2>&1
        fi && log_message "$PLATFORM: added network $_ssid from the card"
    done
}

# At boot: hand the card's networks to NetworkManager, then, if WiFi is wanted
# and not up, let it join whichever is in range and note the address.
darkmoss_wifi_up() {
    command -v nmcli >/dev/null 2>&1 || return 0

    # The one-network bootstrap file this used to read; fold it into the card
    # conf once so nothing is lost, then leave it alone.
    _old="/mnt/SDCARD/Saves/spruce/darkmoss_wifi.conf"
    if [ -f "$_old" ]; then
        _ssid="$(sed -n 's/^SSID=//p' "$_old" | head -1)"
        _psk="$(sed -n 's/^PSK=//p' "$_old" | head -1)"
        [ -n "$_ssid" ] && wpa_conf_save_network "$_ssid" "$_psk" && mv -f "$_old" "$_old.imported"
    fi

    darkmoss_import_card_networks

    wifi_setting_wanted || return 0
    if nmcli -t -f STATE general 2>/dev/null | grep -q "^connected"; then
        log_message "$PLATFORM: already connected"
        return 0
    fi

    (
        nmcli radio wifi on >/dev/null 2>&1
        _wait=0
        while [ "$_wait" -lt 60 ]; do
            _addr="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
            if [ -n "$_addr" ]; then
                darkmoss_ssh_up
                log_message "$PLATFORM: wifi up at $_addr - ssh spruce@$_addr"
                printf '%s\n' "$_addr" > /mnt/SDCARD/Saves/spruce/darkmoss_ip.txt 2>/dev/null
                exit 0
            fi
            # Every 15s, nudge a rescan so a network that came into range gets joined.
            [ $((_wait % 15)) -eq 14 ] && nmcli device wifi rescan >/dev/null 2>&1
            _wait=$((_wait + 1))
            sleep 1
        done
        log_message "$PLATFORM: wifi did not connect after 60s"
    ) &
}
