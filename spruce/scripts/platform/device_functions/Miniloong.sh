#!/bin/sh
# Miniloong Pocket 1 device functions.
#
# The host firmware is the vendor's buildroot image: busybox init, a stock UI
# stack of loong_* daemons that Spruce does NOT run (the rootfs stub blocks
# S50loong for the session), Weston at S49, PulseAudio available but unused,
# glibc 2.38, a writable ext4 rootfs. Spruce reaches this file through the
# rootfs stub -> .tmp_update/updater -> boot session -> runtime.sh chain; see
# ~/ai/CFW/Miniloong/research/rk3566-boot-bootstrap-phase1-20260828.md.
#
# Hardware facts marked UNVERIFIED come from Leaf/Jawaka source
# (Jawaka/internal/platform/device_mlp1.c, input_proxy_mlp1.c,
# miniloong-launcher-switcher/device/mlp1/platform.d/00-audio-init.sh), not
# from a board on the bench. Open items: ~/ai/CFW/Miniloong/TODO.md.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/flip_a30_brightness.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

MINILOONG_INPUT_NODES_FILE="/tmp/miniloong_input_nodes"
MINILOONG_SPK_KEEPER_PID="/tmp/miniloong_spk_keeper.pid"

get_config_path() {
    echo "$SYSTEM_JSON"
}

amixer_card() {
    amixer -c "${MINILOONG_AUDIO_CARD:-1}" "$@"
}

###############################################################################
# Rumble - a PWM channel, not the Flip's GPIO. UNVERIFIED (Jawaka drives
# /sys/class/pwm/pwmchip0/pwm0; unexporting latches the motor ON on this
# driver, so the channel is exported once at boot and never unexported).
###############################################################################

rumble_pwm_dir() {
    echo "/sys/class/pwm/${RUMBLE_PWMCHIP:-pwmchip0}/pwm${RUMBLE_PWM_CHANNEL:-0}"
}

rumble_pwm_init() {
    _chip="/sys/class/pwm/${RUMBLE_PWMCHIP:-pwmchip0}"
    _pwm="$(rumble_pwm_dir)"
    [ -d "$_chip" ] || return 0
    [ -d "$_pwm" ] || echo "${RUMBLE_PWM_CHANNEL:-0}" > "$_chip/export" 2>/dev/null
    [ -d "$_pwm" ] || return 0
    # Order matters: enable off first, then period - a zero period makes every
    # other write on this driver fail with EINVAL.
    echo 0 > "$_pwm/enable" 2>/dev/null
    echo "${RUMBLE_PWM_PERIOD:-1000000}" > "$_pwm/period" 2>/dev/null
    echo normal > "$_pwm/polarity" 2>/dev/null
    echo 0 > "$_pwm/duty_cycle" 2>/dev/null
}

# vibrate [duration_ms] [--intensity Strong|Medium|Weak]
vibrate() {
    _duration=50
    _intensity=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --intensity) _intensity="$2"; shift ;;
            *[!0-9]*) ;;
            *) _duration="$1" ;;
        esac
        shift
    done
    # .rumble_intensity in SYSTEM_JSON is read first for anything that already
    # sets it, but nothing in the tree writes that key - the settings menu
    # writes rumbleIntensity to spruce-config like every other platform. Without
    # the second fallback this device always saw "Medium" and the user's choice,
    # "Off" included, did nothing.
    [ -n "$_intensity" ] || _intensity="$(jq -r '.rumble_intensity // empty' "$SYSTEM_JSON" 2>/dev/null)"
    [ -n "$_intensity" ] || _intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"
    _period="${RUMBLE_PWM_PERIOD:-1000000}"
    # Without this Off lands on the catch-all below and runs the motor at half
    # duty, which is the opposite of what the setting says.
    [ "$_intensity" = "Off" ] && return 0

    case "$_intensity" in
        Strong) _duty=$_period ;;
        Weak)   _duty=$((_period / 4)) ;;
        *)      _duty=$((_period / 2)) ;;
    esac
    _pwm="$(rumble_pwm_dir)"
    [ -d "$_pwm" ] || return 0
    echo "$_duty" > "$_pwm/duty_cycle" 2>/dev/null
    echo 1 > "$_pwm/enable" 2>/dev/null
    sleep "$(awk "BEGIN{print $_duration/1000}")"
    echo 0 > "$_pwm/enable" 2>/dev/null
    echo 0 > "$_pwm/duty_cycle" 2>/dev/null
}

rgb_led() {
    return 0
}

enable_or_disable_rgb() {
    log_message "rgb led not present on the Miniloong Pocket 1" -v
}

###############################################################################
# Audio - rk817 codec on ALSA card 1. Control NAMES are the rk817 driver's
# (shared with the Flip); Leaf addressed the same controls by numid 13 / 16 / 1.
# The speaker amp has its own gate (spk_ctl) that stock loong_service drives:
# it must be raised while a stream is running and dropped for headphones, or
# playback is silent / the speaker keeps playing under the jack. UNVERIFIED.
###############################################################################

are_headphones_plugged_in() {
    amixer_card cget numid=1 2>/dev/null | grep -q 'values=on'
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
}

set_volume() {
    VOLUME_LV="$1"
    SAVE_TO_CONFIG="${2:-true}"
    VOLUME_RAW="$(eval echo "\$SYSTEM_VOLUME_$VOLUME_LV")"
    log_message "Setting volume level $VOLUME_LV (DAC raw ${VOLUME_RAW:-?})"

    if [ "${VOLUME_RAW:-0}" -eq 0 ]; then
        amixer_card sset "Playback Path" "OFF" >/dev/null 2>&1
    else
        amixer_card cset name='DAC Playback Volume' "$VOLUME_RAW,$VOLUME_RAW" >/dev/null 2>&1
        if are_headphones_plugged_in; then
            amixer_card sset "Playback Path" "HP" >/dev/null 2>&1
        else
            amixer_card sset "Playback Path" "SPK" >/dev/null 2>&1
        fi
    fi

    if [ "$SAVE_TO_CONFIG" = true ]; then
        save_volume_to_config_file "$VOLUME_LV"
    fi
}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -gt 0 ]; then
        set_volume "$((VOLUME_LV - 1))"
    fi
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -lt 20 ]; then
        set_volume "$((VOLUME_LV + 1))"
    fi
}

get_current_volume() {
    amixer_card cget name='DAC Playback Volume' 2>/dev/null | sed -n 's/.*: values=\([0-9]*\).*/\1/p' | head -1
}

# Keep the speaker gate in step with playback and the jack, the way stock
# loong_service does. The gate is the only thing that mutes the speaker for
# wired headphones on this codec (Playback Path is a no-op for routing here).
spk_gate_watchdog() {
    _gate="${MINILOONG_SPK_GATE:-/sys/kernel/powerCtrl/spk_ctl}"
    _pcm="/proc/asound/card${MINILOONG_AUDIO_CARD:-1}/pcm0p/sub0/status"
    [ -w "$_gate" ] && [ -r "$_pcm" ] || return 0
    _old="$(cat "$MINILOONG_SPK_KEEPER_PID" 2>/dev/null)"
    [ -n "$_old" ] && [ -d "/proc/$_old" ] && return 0
    (
        while true; do
            if grep -q '^state: RUNNING' "$_pcm" 2>/dev/null; then
                if are_headphones_plugged_in; then
                    echo 0 > "$_gate" 2>/dev/null
                else
                    echo 1 > "$_gate" 2>/dev/null
                fi
            fi
            sleep 0.2
        done
    ) >/dev/null 2>&1 &
    echo "$!" > "$MINILOONG_SPK_KEEPER_PID" 2>/dev/null
}

audio_init() {
    amixer_card sset "Playback Path" "SPK" >/dev/null 2>&1
    set_volume "$(get_volume_level)" false
}

###############################################################################
# Sleep - RK3566 suspend-to-RAM, the same path as the Flip.
###############################################################################

WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

trigger_device_sleep() {
    echo deep >/sys/power/mem_sleep 2>/dev/null
    echo -n mem >/sys/power/state
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

device_exit_sleep() {
    set_volume "$(get_volume_level)" false
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
}

device_lid_sensor_ready() {
    return 1
}

device_lid_open() {
    return 1
}

###############################################################################
# Boot-time setup
###############################################################################

# Power and volume key nodes, asked of the kernel rather than guessed
# (RGB30 precedent). The pad has its own by-path link.
node_reports_key() {
    _caps="/sys/class/input/$1/device/capabilities/key"
    _key="$2"
    [ -r "$_caps" ] || return 1
    awk -v key="$_key" '{
        s=""
        for (i=1; i<=NF; i++) { w=$i; if (i>1) { while (length(w)<16) w="0" w } s=s w }
        nib=int(key/4); bit=key%4; pos=length(s)-nib
        if (pos < 1) exit 1
        c=tolower(substr(s,pos,1)); v=index("0123456789abcdef",c)-1
        if (v < 0) exit 1
        exit (int(v/(2^bit))%2 == 1) ? 0 : 1
    }' "$_caps"
}

resolve_key_event_node() {
    _power=""
    _volume=""
    _seen=""
    for _dir in /sys/class/input/event*; do
        [ -e "$_dir" ] || continue
        _ev=$(basename "$_dir")
        _name=$(cat "$_dir/device/name" 2>/dev/null)
        _seen="$_seen ${_ev}:${_name}"
        if [ -z "$_volume" ] && node_reports_key "$_ev" 114 && node_reports_key "$_ev" 115; then
            _volume="/dev/input/$_ev"
        fi
        case "$_name" in
            *pwrkey*|*Power*|*power*) [ -z "$_power" ] && _power="/dev/input/$_ev" ;;
        esac
    done
    log_message "Miniloong: input nodes:$_seen"

    # Resolve the gamepad by evdev NAME ("Loong Gamepad"); the stock firmware
    # does not reliably create the by-path link the cfg defaults to, and a wrong
    # node means no input -> idlemon sees no activity and PyUI screensavers to a
    # black screen. Verified on hardware: the pad is "Loong Gamepad" (event4).
    _pad=""
    for _dir in /sys/class/input/event*; do
        [ -e "$_dir" ] || continue
        _ev=$(basename "$_dir")
        if [ "$(cat "$_dir/device/name" 2>/dev/null)" = "Loong Gamepad" ]; then
            _pad="/dev/input/$_ev"
            break
        fi
    done
    if [ -n "$_pad" ] && [ -c "$_pad" ]; then
        export EVENT_PATH_READ_INPUTS_SPRUCE="$_pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$_pad"
        export EVENT_PATH_SEND_TO_DRASTIC="$_pad"
        log_message "Miniloong: gamepad 'Loong Gamepad' at $_pad"
    else
        log_message "Miniloong: 'Loong Gamepad' node not found; leaving $EVENT_PATH_READ_INPUTS_SPRUCE"
    fi

    if [ -n "$_power" ] && [ -c "$_power" ]; then
        export EVENT_PATH_POWER="$_power"
    fi
    if [ -n "$_volume" ] && [ -c "$_volume" ]; then
        export EVENT_PATH_VOLUME="$_volume"
        log_message "Miniloong: volume keys on $_volume"
    else
        # No dedicated rocker (Leaf implements volume as Menu chords on this
        # board). Point the volume watchdog at the power node so it idles
        # harmlessly instead of failing to open a missing device.
        export EVENT_PATH_VOLUME="$EVENT_PATH_POWER"
        log_message "Miniloong: no node reports volume keys; volume watchdog idles on $EVENT_PATH_VOLUME"
    fi
    {
        echo "EVENT_PATH_READ_INPUTS_SPRUCE='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_SEND_TO_RA_AND_PPSSPP='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_SEND_TO_DRASTIC='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_VOLUME='${EVENT_PATH_VOLUME}'"
        echo "EVENT_PATH_POWER='${EVENT_PATH_POWER}'"
    } > "$MINILOONG_INPUT_NODES_FILE" 2>/dev/null
}

setup_mainui_alias() {
    MAINUI="/mnt/SDCARD/spruce/flip/bin/MainUI"
    PY="/mnt/SDCARD/spruce/flip/bin/python3.10"
    [ -f "$PY" ] || { log_message "Miniloong: $PY missing - PyUI cannot start"; return 1; }
    if [ -s "$MAINUI" ] && [ "$(stat -c%s "$MAINUI" 2>/dev/null)" = "$(stat -c%s "$PY" 2>/dev/null)" ]; then
        return 0
    fi
    touch "$MAINUI" 2>/dev/null
    mount -o bind "$PY" "$MAINUI" 2>/dev/null
    if [ ! -s "$MAINUI" ]; then
        umount "$MAINUI" 2>/dev/null
        cp "$PY" "$MAINUI" || { log_message "Miniloong: could not create MainUI"; return 1; }
        chmod +x "$MAINUI" 2>/dev/null
    fi
}

# Stock Weston owns the DRM master. PyUI/RetroArch on KMSDRM cannot open the
# display while it runs, so the KMSDRM route stops it (MINILOONG_STOP_WESTON=1).
# The Wayland route leaves it up and sets SDL_VIDEODRIVER=wayland instead.
stop_weston_if_configured() {
    [ "${MINILOONG_STOP_WESTON:-1}" = "1" ] || return 0
    pgrep -x weston >/dev/null 2>&1 || return 0
    if [ -x /etc/init.d/S49weston ]; then
        /etc/init.d/S49weston stop >/dev/null 2>&1
    else
        killall weston 2>/dev/null
    fi
    _i=0
    while pgrep -x weston >/dev/null 2>&1 && [ "$_i" -lt 30 ]; do
        sleep 0.1
        _i=$((_i + 1))
    done
    log_message "Miniloong: stopped Weston for KMSDRM (waited $_i x 100ms)"
}

runtime_mounts_Miniloong() {
    # The rootfs stub binds the card over /mnt/SDCARD; make sure of it when
    # this is entered another way (a developer running runtime.sh by hand).
    if [ ! -e /mnt/SDCARD/spruce/scripts/runtime.sh ] && [ -d /mnt/sdcard/spruce ]; then
        mkdir -p /mnt/SDCARD 2>/dev/null
        mount --bind /mnt/sdcard /mnt/SDCARD 2>/dev/null
    fi
    for _f in profile group passwd; do
        [ -f "$SPRUCE_ETC_DIR/$_f" ] && mount -o bind "$SPRUCE_ETC_DIR/$_f" "/etc/$_f" 2>/dev/null
    done
    touch /mnt/SDCARD/spruce/flip/bin/MainUI 2>/dev/null
    /mnt/SDCARD/spruce/flip/recombine_large_files.sh >> /mnt/SDCARD/Saves/spruce/spruce.log 2>&1
}

# Spruce's dropbearmulti authenticates against /etc/passwd + /etc/shadow, and the
# stock loong rootfs ships no "spruce" account, so spruce/happygaming (and Samba's
# `smbpasswd -a spruce`) have nothing to authenticate and ssh is refused.
#
# PRIMARY path: spruce/miniloong/etc/passwd (a superset of the captured stock
# accounts + a root-equivalent spruce with its hash inline, no shadow needed - the
# miyoomini pattern) is bind-mounted over /etc/passwd by runtime_mounts_Miniloong,
# which runs first. This function is then the FALLBACK: its `grep '^spruce:'` guard
# makes it a no-op whenever that static passwd is present, and it only does the
# work if the payload lacks the file or a stock-firmware update replaced
# /etc/passwd out from under the bind. Inject a root-equivalent spruce user by
# bind-mounting patched copies over the stock files - ephemeral, re-applied each
# boot. Mirrors AnbernicXXCommon.add_spruce_system_user.
add_spruce_system_user() {
    grep -q '^spruce:' /etc/passwd 2>/dev/null && return 0

    SP_HASH='$6$spruceos00$.nwqRlVkLe.wmkXcEHXcu127ZFxpFQ.8JDbdh4CRd.FbF5biVcIl9qeE9T6QNAbbJaFKp3MLUwlaPUN0alXcl.'
    cp /etc/passwd /tmp/spruce_passwd 2>/dev/null || return 0
    if cp /etc/shadow /tmp/spruce_shadow 2>/dev/null; then
        echo 'spruce:x:0:0:spruce:/root:/bin/sh' >> /tmp/spruce_passwd
        echo "spruce:${SP_HASH}:19000:0:99999:7:::" >> /tmp/spruce_shadow
        chmod 644 /tmp/spruce_passwd
        chmod 600 /tmp/spruce_shadow
        mount -o bind /tmp/spruce_passwd /etc/passwd 2>/dev/null
        mount -o bind /tmp/spruce_shadow /etc/shadow 2>/dev/null
    else
        # No /etc/shadow on this rootfs: carry the hash inline in passwd, which
        # dropbear reads when the password field is not "x".
        echo "spruce:${SP_HASH}:0:0:spruce:/root:/bin/sh" >> /tmp/spruce_passwd
        chmod 644 /tmp/spruce_passwd
        mount -o bind /tmp/spruce_passwd /etc/passwd 2>/dev/null
    fi
    log_message "Miniloong: provisioned spruce login for dropbear/samba"
}

device_init() {
    runtime_mounts_Miniloong
    add_spruce_system_user
    echo 3 > /proc/sys/kernel/printk
    export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:/usr/lib:/lib"
    rumble_pwm_init
    resolve_key_event_node
    setup_mainui_alias
    stop_weston_if_configured
    audio_init
    [ -e "$EVENT_PATH_READ_INPUTS_SPRUCE" ] || \
        log_message "Miniloong: pad node $EVENT_PATH_READ_INPUTS_SPRUCE missing - controls will be dead"
}

launch_startup_watchdogs() {
    launch_common_startup_watchdogs_v2
    spk_gate_watchdog
    /mnt/SDCARD/spruce/scripts/enable_zram.sh &
}

# principal.sh calls these around the PyUI launch; device.sh only stubs them with
# a "Missing ..." log, so without them the Miniloong just eats the warning and
# gets no boost. Adopt the RGB30's version - the sibling RK3566/Mali-G52 port -
# NOT the Flip's, which also pins /sys/class/devfreq/dmc at "performance" for the
# rest of the session. SDL2/KMSDRM startup is the slowest step to the menu here
# (see MLP1-019), and the CPU is what it waits on: run the governor flat out for
# the first few seconds, then drop back to smart once the menu is up.
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

set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}

check_if_fw_needs_update() {
    echo "false"
}

take_screenshot() {
    /mnt/SDCARD/spruce/flip/screenshot.sh "$1"
}

set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
    log_message "Resetting RetroArch hotkeys to Spruce defaults."
    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"4\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"9\"" \
        "input_menu_toggle = \"escape\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_save_state_btn = \"10\"" \
        "input_screenshot_btn = \"1\"" \
        "input_shader_toggle_btn = \"11\"" \
        "input_state_slot_decrease_btn = \"13\"" \
        "input_state_slot_increase_btn = \"14\"" \
        "input_toggle_slowmotion_axis = \"+4\"" \
        "input_toggle_fast_forward_axis = \"+5\""
}

setup_for_retroarch() {
    if [ "$CORE" = "uae4arm" ]; then
        export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
    elif [ "$CORE" = "easyrpg" ]; then
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
    elif [ "$CORE" = "yabasanshiro" ]; then
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
    fi
    export CORE_DIR="$RA_DIR/.retroarch/cores64"
    if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
        export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
    else
        export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
    fi
}

new_execution_loop() {
    log_message "new_execution_loop unneeded on this device" -v
}

device_get_charging_status() {
    cat "$BATTERY/status"
}

device_get_battery_percent() {
    cat "$BATTERY/capacity"
}

device_prepare_for_ports_run() {
    log_message "device_prepare_for_ports_run unneeded" -v
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run unneeded" -v
}

# Spruce manages WiFi here. The stock network init runs (S40network < S49spruce)
# but only auto-connects through the vendor UI / loong_daemon, which Spruce
# bypasses - so left to stock, wlan0 never associates. Spruce therefore owns
# wpa_supplicant (-D nl80211) + udhcpc and the PyUI WiFi menu, the same as the
# Flip. (return 1 = false = "spruce manages it".)
device_manages_own_wifi() {
    return 1
}

device_wifi_power_on() {
    [ -w /sys/class/rkwifi/wifi_power ] && echo 1 > /sys/class/rkwifi/wifi_power
    sleep 1
}

device_wifi_power_off() {
    [ -w /sys/class/rkwifi/wifi_power ] && echo 0 > /sys/class/rkwifi/wifi_power
}

device_system_handles_sdcard_unmount() {
    return 1
}

# Power transitions. The stock busybox `poweroff`/`reboot` only signal PID 1,
# and init is blocked in rcS for the whole Spruce session (S49spruce ->
# session.sh -> runtime.sh), so they return having done nothing: three shutdown
# attempts on 2026-08-28 and two on 2026-09-04 all ended at "Attempting to
# unmount /mnt/SDCARD" with the device still up (SPR-HIGH-051). Magic SysRq is
# 0 by default here. So: opt into the strict unmount path (which also sets the
# shutting_down flag the boot session reads, so runtime's exit is a clean
# shutdown and not a crash to relaunch), tell stage 2 the applets cannot be
# trusted, and when we must do it ourselves take the filesystems down the
# REISUB way and call the forced form - reboot(2), no init involved. Sequence
# per Jawaka device_mlp1.c, which measured FAT corruption on this board without
# the emergency remount-ro.
device_needs_strict_unmount() {
    return 0
}

device_power_transition_bypasses_init() {
    return 0
}

# The rk817 (i2c-0, 0x20) ships with SYS_CFG3 (0xF4) bits 7:6 = 00, Rockchip's
# RST_FUNC_DEV "reset the dev": a SoC reset makes the PMIC power-cycle every rail,
# and on this unit that ends with the board OFF - a menu reboot and an ssh
# `reboot -f` both left it dark (2026-09-04). Rockchip's own driver flips the
# field to RST_FUNC_REG (0x1<<6, "reset the reg only") before loader/recovery/
# fastboot/panic/watchdog reboots and leaves plain reboots on the power-cycling
# mode. Doing the same flip before OUR plain reboot brought the unit back in
# 19 s (04:19:25 -> up, uptime 15 s). Read-modify-write so the SLPPIN and other
# bits keep whatever the driver set; -f because the rk808 driver owns 0x20.
MINILOONG_PMIC_I2C_BUS="${MINILOONG_PMIC_I2C_BUS:-0}"
MINILOONG_PMIC_I2C_ADDR="${MINILOONG_PMIC_I2C_ADDR:-0x20}"
MINILOONG_PMIC_SYS_CFG3="0xf4"

miniloong_pmic_reset_registers_only() {
    _cur="$(i2cget -f -y "$MINILOONG_PMIC_I2C_BUS" "$MINILOONG_PMIC_I2C_ADDR" "$MINILOONG_PMIC_SYS_CFG3" 2>/dev/null)"
    case "$_cur" in 0x[0-9a-fA-F][0-9a-fA-F]) ;; *) _cur=0x18 ;; esac
    _new=$(( (_cur & 0x3f) | 0x40 ))
    i2cset -f -y "$MINILOONG_PMIC_I2C_BUS" "$MINILOONG_PMIC_I2C_ADDR" "$MINILOONG_PMIC_SYS_CFG3" "$_new" 2>/dev/null
    log_message "Miniloong: rk817 SYS_CFG3 $_cur -> $(printf '0x%02x' "$_new") (reset registers only) before reboot"
}

device_prepare_for_reboot() {
    miniloong_pmic_reset_registers_only
}

miniloong_forced_power_transition() {
    # $1 = poweroff | reboot
    _sysrq_ctl="${SPRUCE_SYSRQ_CTL:-/proc/sys/kernel/sysrq}"
    _sysrq_trigger="${SPRUCE_SYSRQ_TRIGGER:-/proc/sysrq-trigger}"
    [ "$1" = "reboot" ] && miniloong_pmic_reset_registers_only
    echo 1 > "$_sysrq_ctl" 2>/dev/null
    sync
    echo s > "$_sysrq_trigger" 2>/dev/null
    echo u > "$_sysrq_trigger" 2>/dev/null
    echo s > "$_sysrq_trigger" 2>/dev/null
    sleep 0.5
    "$1" -f
    sleep 3
    case "$1" in
        reboot) echo b > "$_sysrq_trigger" 2>/dev/null ;;
        *) echo o > "$_sysrq_trigger" 2>/dev/null ;;
    esac
}

run_poweroff_cmd() {
    miniloong_forced_power_transition poweroff
}

device_run_reboot_cmd() {
    miniloong_forced_power_transition reboot
}

# The rootfs stub (spruce/miniloong/S50spruce) owns the hand-off to stock
# S50loong: the session just returns to it, so there is nothing to exec here.
device_stock_ui_command() {
    printf ''
}
