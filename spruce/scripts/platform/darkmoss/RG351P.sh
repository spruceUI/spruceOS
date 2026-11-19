#!/bin/sh
# Anbernic RG351P device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit. Board,
# codec and memory behave as on the V10 (V10.sh), the pad and the motor do not.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"

# No onboard radio: Wi-Fi is a USB dongle that may or may not be plugged in.
# A radio exists while a dongle's driver has registered a wireless interface.
# NetworkManager's radio-off (an rfkill soft block) keeps the interface, so
# this answers whether the hardware is there, not whether Wi-Fi is switched on.
device_has_wifi_radio() {
    for _rg351p_w in /sys/class/net/*/phy80211 /sys/class/net/*/wireless; do
        [ -e "$_rg351p_w" ] && return 0
    done
    return 1
}

device_wifi_is_available() {
    device_has_wifi_radio
}

# The rk817's "Playback Path" has to be SPK_HP, as ArkOS sets it on its RK3326
# units (dArkMoss's spktoggle.sh): both outputs powered, and the kernel's jack
# detection (hp-det-gpio in rk3326-rg351p-linux.dts) mutes the speaker while
# headphones are in. On SPK the headphone output stays off: plugging in still
# muted the speaker, and the headphones got nothing (seen on hardware). Only
# written when it differs, so the many calls (boot, wake, every volume change)
# do not re-power the outputs and pop.
RG351P_PLAYBACK_PATH="SPK_HP"
apply_playback_path() {
    _path="$(amixer sget 'Playback Path' 2>/dev/null | sed -n "s/^ *Item0: '\(.*\)'$/\1/p")"
    [ "$_path" = "$RG351P_PLAYBACK_PATH" ] && return 0
    amixer -q sset 'Playback Path' "$RG351P_PLAYBACK_PATH" 2>/dev/null
    log_message "$PLATFORM: Playback Path ${_path:-unknown} -> $RG351P_PLAYBACK_PATH"
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}

# The internal output's volume is the hardware wheel, after the codec. spruce
# keeps everything in front of it at full, whatever level it is asked for, and
# nothing here steps it. "Everything" is two controls: the codec's own
# "Playback" and the softvol "Master" that all of spruce's audio goes through
# (dArkMossCommon's .asoundrc), which alsa-restore brings back at whatever
# level it was saved at: pinning only "Playback" left audio quiet with the
# wheel at max (seen on hardware). Master only exists once a stream has opened
# the softvol PCM, so a short burst of silence through it creates the control
# first when it is missing.
#
# A Bluetooth headset sits outside the wheel, so the requested 0-20 level goes
# to the headset (bt_headset_volume) and is what gets saved: the codec ignores
# the saved level (it is pinned at 100% either way), so .vol carries the
# headset level, and device_bt_audio_connected restores it on reconnect.
#
# The one exception is a temporary mute that is not saved (sleep_helper.sh
# mutes with "set_volume 0 false" so waking to shut down is silent, then
# restores). It applies only while sleep_helper's /tmp/sleep_helper_started
# directory exists: .vol holds the headset level, so 0 is a real user choice
# and every other "set_volume 0 false" (PyUI's apply_volume, pico8,
# darkmoss_exit_sleep) must take the normal path and silence the headset.
RG351P_VOLUME_CONTROLS="Playback Master"
set_volume() {
    if [ "$1" = "0" ] && [ "${2:-true}" = "false" ] && [ -d /tmp/sleep_helper_started ]; then
        amixer -q sset -M "${VOLUME_CONTROL:-Playback}" 0% 2>/dev/null
        log_message "$PLATFORM: codec muted (temporary)"
        return 0
    fi
    _lvl="$1"
    case "$_lvl" in
        ''|*[!0-9]*) _lvl=20 ;;
    esac
    [ "$_lvl" -gt 20 ] && _lvl=20
    amixer sget Master >/dev/null 2>&1 ||
        head -c 400 /dev/zero | timeout 2 aplay -q -N -D softvol -t raw -f S16_LE -r 44100 -c 2 >/dev/null 2>&1
    for _ctl in $RG351P_VOLUME_CONTROLS; do
        amixer -q sset -M "$_ctl" 100% 2>/dev/null
    done
    bt_headset_volume "$_lvl"
    apply_playback_path
    if [ "${2:-true}" = "true" ]; then
        save_volume_to_config_file "$_lvl" 2>/dev/null
    fi
}

# asound-setup.sh calls this with the headset's MAC after routing to it, or
# with nothing for the internal output. Only remembered for PyUI (rg351p.py
# shows the volume setting while a headset is routed): nothing is re-pinned or
# saved on disconnect, the codec is already at 100% and the headset level is
# kept for the next connect.
device_on_bt_audio_route() {
    if [ -n "$1" ]; then
        touch /tmp/rg351p_bt_route
    else
        rm -f /tmp/rg351p_bt_route
    fi
}

volume_up() {
    :
}

volume_down() {
    :
}

# A real stick and a hat d-pad: nothing to swap.
swap_dpad_analog_toggle() {
    :
}

treat_dpad_as_analog() {
    :
}

treat_dpad_as_dpad() {
    :
}

device_get_charging_status() {
    if grep -qs "^1$" /sys/class/power_supply/ac/online /sys/class/power_supply/usb/online; then
        if [ "$(cat "$BATTERY/capacity" 2>/dev/null)" = "100" ]; then
            echo "Full"
        else
            echo "Charging"
        fi
    else
        echo "Discharging"
    fi
}

# The kernel powers the unit off by itself near empty: rk817_bat_lowpwr_check
# (rk817_battery.c, CONFIG_ARCH_ROCKCHIP_ODROIDGOA) calls orderly_poweroff once
# the average voltage stays under power_off_thresd (3400 mV in
# rk3326-rg351p-linux.dts) for a minute while discharging, or at once at
# 3350 mV. That stop never runs save_poweroff.sh, and the gauge (and
# BatteryPlus, whose empty point is lower) can still read several percent
# there. So near the cut-off this reports 1%, and battery_level_watchdog's
# save-and-shutdown runs first: at once at 3.40 V or less, or once the voltage
# has stayed under 3.45 V for 20 s (a single load dip does not count). The
# stamp resets on the charger or when the voltage recovers. Otherwise this is
# dArkMossCommon's: BatteryPlus's percent when its file holds 0-100, else the
# kernel's.
RG351P_VBAT_SAVE_UV=3450000   # sustained under this: 50 mV above the kernel threshold
RG351P_VBAT_NOW_UV=3400000    # at or under this: the kernel's one-minute timer is running
RG351P_VBAT_HOLD_S=20
RG351P_VBAT_STAMP="/tmp/rg351p_vbat_low_since"
RG351P_VBAT_LOGGED="/tmp/rg351p_vbat_logged"
device_get_battery_percent() {
    _pct=""
    if [ -n "$BATTERYPLUS_PERCENT_FILE" ]; then
        _bp=$(cat "$BATTERYPLUS_PERCENT_FILE" 2>/dev/null)
        case "$_bp" in
            ''|*[!0-9]*) ;;
            *) [ "$_bp" -le 100 ] && _pct="$_bp" ;;
        esac
    fi
    [ -n "$_pct" ] || _pct=$(cat "$BATTERY/capacity" 2>/dev/null || echo 0)

    _uv=$(cat "$BATTERY/voltage_now" 2>/dev/null)
    case "$_uv" in
        ''|*[!0-9]*) rm -f "$RG351P_VBAT_STAMP"; echo "$_pct"; return ;;
    esac
    if grep -qs "^1$" /sys/class/power_supply/ac/online /sys/class/power_supply/usb/online \
        || [ "$_uv" -ge "$RG351P_VBAT_SAVE_UV" ]; then
        rm -f "$RG351P_VBAT_STAMP"
        echo "$_pct"
        return
    fi
    _now=$(cut -d. -f1 /proc/uptime 2>/dev/null)
    case "$_now" in ''|*[!0-9]*) _now=0 ;; esac
    [ -f "$RG351P_VBAT_STAMP" ] || echo "$_now" > "$RG351P_VBAT_STAMP" 2>/dev/null
    _since=$(cat "$RG351P_VBAT_STAMP" 2>/dev/null)
    case "$_since" in ''|*[!0-9]*) _since="$_now" ;; esac
    if [ "$_uv" -le "$RG351P_VBAT_NOW_UV" ] || [ $((_now - _since)) -ge "$RG351P_VBAT_HOLD_S" ]; then
        if [ ! -e "$RG351P_VBAT_LOGGED" ]; then
            log_message "$PLATFORM battery: ${_uv}uV near the kernel's 3.4 V power-off (gauge ${_pct}%), reporting 1%"
            touch "$RG351P_VBAT_LOGGED" 2>/dev/null
        fi
        echo 1
        return
    fi
    echo "$_pct"
}

# As the V10: memory clock changes make the sound crackle, so pin it.
set_dram_governor() {
    [ -n "$DRAM_DEVFREQ_DIR" ] && [ -d "$DRAM_DEVFREQ_DIR" ] || return 0
    _top=$(tr ' ' '\n' < "$DRAM_DEVFREQ_DIR/available_frequencies" 2>/dev/null | grep -v '^$' | sort -n | tail -1)
    [ -n "$_top" ] || return 0
    echo userspace > "$DRAM_DEVFREQ_DIR/governor" 2>/dev/null
    echo "$_top" > "$DRAM_DEVFREQ_DIR/userspace/set_freq" 2>/dev/null
    echo "$_top" > "$DRAM_DEVFREQ_DIR/min_freq" 2>/dev/null
}

# The motor hangs off pwm0 (GPIO0_B7) and runs while the pin is high (the
# V10's dtb, holding that pin high, left it running nonstop). It is not a
# force-feedback device on the pad, so darkmoss_vibrate's rumble tool has
# nothing to talk to: drive the PWM through sysfs.
#
# The 4.4 Rockchip driver reports "inversed" for this PWM and does not let
# sysfs change it, so work in whichever polarity it reports, as AmberELEC does
# on this board: with "inversed" the duty cycle is the low time, a disabled
# PWM idles high (motor on), and off is enabled with duty = period; with
# "normal" off is duty 0, disabled. Never leave an inversed PWM disabled.
RG351P_PWM_PERIOD=1000000
_rg351p_pwm() {
    _chip="${RG351P_PWM_CHIP:-/sys/class/pwm/pwmchip0}"
    [ -d "$_chip" ] || return 1
    [ -d "$_chip/pwm0" ] || echo 0 2>/dev/null > "$_chip/export"
    [ -d "$_chip/pwm0" ] || return 1
    echo "$_chip/pwm0"
}

_rg351p_pwm_inversed() {
    [ "$(cat "$1/polarity" 2>/dev/null)" = "inversed" ]
}

# Duty $2 (0..period) as the motor's on-fraction, in either polarity.
_rg351p_motor_set() {
    _rg351p_d="$2"
    _rg351p_pwm_inversed "$1" && _rg351p_d=$((RG351P_PWM_PERIOD - $2))
    # period before duty_cycle: the kernel refuses a duty longer than the period.
    echo "$RG351P_PWM_PERIOD" 2>/dev/null > "$1/period"
    echo "$_rg351p_d" 2>/dev/null > "$1/duty_cycle"
    echo 1 2>/dev/null > "$1/enable"
}

_rg351p_motor_off() {
    if _rg351p_pwm_inversed "$1"; then
        _rg351p_motor_set "$1" 0
    else
        echo 0 2>/dev/null > "$1/duty_cycle"
        echo 0 2>/dev/null > "$1/enable"
    fi
}

# For wake: off only if pwm0 is exported (rumble never ran since boot
# otherwise, and the dtb leaves the pin low).
_rg351p_motor_safe_off() {
    _rg351p_c="${RG351P_PWM_CHIP:-/sys/class/pwm/pwmchip0}"
    [ -d "$_rg351p_c/pwm0" ] || return 0
    _rg351p_motor_off "$_rg351p_c/pwm0"
}

vibrate() {
    duration=""
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity) shift; intensity="$1" ;;
        [0-9]*) duration="$1" ;;
        esac
        shift
    done

    case "$intensity" in
        "Off")    return 0 ;;
        "Weak")   duty=$((RG351P_PWM_PERIOD * 6 / 10)); tier_duration=200 ;;
        "Strong") duty=$RG351P_PWM_PERIOD;              tier_duration=450 ;;
        *)        duty=$((RG351P_PWM_PERIOD * 8 / 10)); tier_duration=300 ;;
    esac
    [ -n "$duration" ] || duration="$tier_duration"

    _pwm="$(_rg351p_pwm)" || return 0
    # In a subshell with a trap, so the motor goes off however the buzz ends:
    # a TERM/INT/HUP (killall of the calling script) interrupts the wait and
    # still turns it off. The sleep runs in the background and is waited for,
    # because a trapped signal only runs once a foreground command has ended.
    (
        trap '_rg351p_motor_off "$_pwm"' EXIT
        trap 'exit 1' INT TERM HUP
        _rg351p_motor_set "$_pwm" "$duty"
        sleep "$(awk -v ms="$duration" 'BEGIN { printf "%.3f", ms / 1000 }')" &
        wait $!
    )
    _rg351p_motor_off "$_pwm"
}

# The pad is a USB device behind a USB hub on the dwc2 controller, and every
# suspend re-enumerates it: the base OS sleep hook,
# /usr/lib/systemd/system-sleep/sleep (dArkMoss scripts/sleep.rk3326), unloads
# dwc2 before suspend and reloads it after, so the pad's input device goes away
# and comes back as a new one. PyUI reopens its node by itself
# (KeyWatcherController), but menubutton_watchdog.sh and buttons_watchdog.sh
# read it through getevent, which stays on the old device: after waking, the
# stick click no longer opened the menu (seen on hardware). A getevent that
# outlives its device cannot be told from a working one from outside, so the
# readers are restarted after every wake, once the pad is back.
#
# darkmoss's trigger_device_sleep waits for systemd-suspend.service, which
# includes that hook, so the pad is normally back already when
# device_exit_sleep runs. Back means a new input device: the kernel numbers
# each one afresh (input2, input3, ...), so the pad's number is kept in
# RG351P_PAD_INPUT_FILE and the re-arm waits up to 10 s for it to change; if it
# does not (no re-enumeration), the readers are restarted all the same. If the
# pad is missing altogether, it waits up to a minute in all for it to appear,
# and restarts nothing on a missing node (a getevent on it would exit for good).
#
# Ordering: sleep_helper.sh calls device_exit_sleep, waits 2 s, removes
# /tmp/sleep_helper_started and starts idle_watchdog.sh itself. The re-arm runs
# in the background and first waits for that, so its restart_pad_readers
# (watchdog_launcher.sh's helper for a re-created pad node, which also starts
# idle_watchdog.sh) comes after it and replaces its idlemons. Each wake bumps a
# generation number (RG351P_REARM_GEN_FILE): a re-arm gives up as soon as a
# newer wake superseded it or a new sleep began (sleep_helper's directory is
# back), and the restart itself runs under a lock directory, so overlapping
# re-arms never start two sets of watchdogs.
# Standalone programs that keep running on their own: Songo#5's Godot runtime
# (sbc_4_3_rcv12, which draws through the system libSDL2, the odroidgoa KMSDRM
# build that rotates each frame for this portrait panel with an RGA blit; it
# has no librga of its own), ScummVM, GameTank, BigPEmu, XRoar and the media
# players. They are paused across a sleep like the emulators (signal_emulators
# STOP/CONT), so a timed wake does not run them in the dark, and save_poweroff
# now sends them CONT, then TERM, then KILL like the emulators.
for _p in sbc_4_3_rcv12 scummvm.64 GameTankEmulator bigpemu xroar gvu ffplay; do
    case " $EMU_PROCESSES " in
        *" $_p "*) ;;
        *) EMU_PROCESSES="$EMU_PROCESSES $_p" ;;
    esac
done
unset _p

RG351P_PAD_NAME="OpenSimHardware OSH PB Controller"
RG351P_PAD_INPUT_FILE="/tmp/rg351p_pad_input"
RG351P_REARM_GEN_FILE="/tmp/rg351p_rearm_gen"
RG351P_REARM_LOCK="/tmp/rg351p_rearm.lock"

# Pad proxy (rg351p_padproxy.py): the pad loses power in suspend and comes back
# as a new input device on every wake, and programs that open it once (vtree,
# Songo, most SDL apps) keep the dead one. The proxy grabs the real pad and
# mirrors it into a virtual one with the same name and IDs that never goes
# away; a runtime udev rule hides the real pad from joystick scans meanwhile.
# The virtual device's phys is "rg351p-padproxy". Supervised by a shell loop
# that restarts it with the rule kept, and gives up after 5 quick failures in a
# row; only that give-up removes the rule, so games never stay without a
# joystick.
RG351P_PADPROXY="/mnt/SDCARD/spruce/scripts/platform/darkmoss/rg351p_padproxy.py"
RG351P_PADPROXY_PID="/tmp/rg351p_padproxy.pid"
RG351P_PADPROXY_LOG="/mnt/SDCARD/Saves/spruce/rg351p-padproxy.log"
RG351P_PADPROXY_PHYS="rg351p-padproxy"
RG351P_PADPROXY_RULE="/run/udev/rules.d/99-rg351p-padproxy.rules"

_rg351p_padproxy_alive() {
    _rg351p_pp=""
    read -r _rg351p_pp 2>/dev/null < "$RG351P_PADPROXY_PID"
    [ -n "$_rg351p_pp" ] && kill -0 "$_rg351p_pp" 2>/dev/null
}

# A proxy restart or give-up, or a proxy that came up after boot's wait, moved
# the pad node: put spruce's readers (the watchdogs' getevents, idlemon) on the
# current one. $1 is how many seconds to wait for the virtual node first (0:
# do not wait, after a give-up). Boot's launch_common_startup_watchdogs_v2
# starts the readers the first time, so this waits for them (up to a minute)
# and leaves a wake to that wake's re-arm. Same lock as the re-arm.
_rg351p_padproxy_follow() {
    _i=0
    while [ "$_i" -lt $(( $1 * 4 )) ] && ! _rg351p_padproxy_node_up; do
        sleep 0.25
        _i=$((_i + 1))
    done
    _i=0
    until pgrep -f /mnt/SDCARD/spruce/scripts/menubutton_watchdog.sh >/dev/null 2>&1; do
        [ "$_i" -ge 240 ] && return 0
        sleep 0.25
        _i=$((_i + 1))
    done
    sleep 0.5
    [ -d /tmp/sleep_helper_started ] && return 0
    _now="$(_rg351p_pad_input_id)"
    _rec=""
    read -r _rec 2>/dev/null < "$RG351P_PAD_INPUT_FILE"
    [ -n "$_now" ] && [ "$_now" != "$_rec" ] || return 0
    _w=0
    until mkdir "$RG351P_REARM_LOCK" 2>/dev/null; do
        [ "$_w" -ge 20 ] && return 0
        sleep 0.25
        _w=$((_w + 1))
    done
    # Another follower or a re-arm may have moved the readers while this one
    # waited for the lock: check again, so they are not restarted twice.
    _rec=""
    read -r _rec 2>/dev/null < "$RG351P_PAD_INPUT_FILE"
    _now="$(_rg351p_pad_input_id)"
    if [ -z "$_now" ] || [ "$_now" = "$_rec" ]; then
        rmdir "$RG351P_REARM_LOCK" 2>/dev/null
        return 0
    fi
    log_message "$PLATFORM: pad node moved to $_now, restarting the pad readers"
    echo "$_now" > "$RG351P_PAD_INPUT_FILE"
    resolve_pad_node rearm
    resolve_key_event_node
    rm -f /tmp/menubtn /tmp/menubtn_cancelled
    killall -q idlemon 2>/dev/null
    restart_pad_readers
    rmdir "$RG351P_REARM_LOCK" 2>/dev/null
}

# The hide rule stays while the proxy restarts: a crash then only removes the
# virtual pad, and the restarted proxy's new one is added while the real pad is
# still hidden, so RetroArch puts it back on port 1. Only a give-up shows the
# real pad again. Every restart is followed by _rg351p_padproxy_follow.
_rg351p_padproxy_start() {
    _rg351p_padproxy_alive && return 0
    [ -x /usr/bin/python3 ] && [ -e /dev/uinput ] && [ -f "$RG351P_PADPROXY" ] || return 1
    : > "$RG351P_PADPROXY_LOG" 2>/dev/null
    (
        trap '' HUP
        _fails=0
        _first=1
        while [ "$_fails" -lt 5 ]; do
            [ "$_first" = 1 ] || _rg351p_padproxy_follow 10 </dev/null >/dev/null 2>&1 &
            _first=0
            _t0=$(date +%s)
            # Ahead of the games it feeds, so a busy core does not delay the pad.
            if command -v nice >/dev/null 2>&1; then
                nice -n -10 /usr/bin/python3 -I "$RG351P_PADPROXY" >> "$RG351P_PADPROXY_LOG" 2>&1
            else
                /usr/bin/python3 -I "$RG351P_PADPROXY" >> "$RG351P_PADPROXY_LOG" 2>&1
            fi
            if [ $(( $(date +%s) - _t0 )) -lt 60 ]; then _fails=$((_fails + 1)); else _fails=0; fi
            echo "padproxy exited, restart $_fails/5" >> "$RG351P_PADPROXY_LOG"
            sleep 2
        done
        # Giving up: show the real pad to joystick scans again. Running SDL
        # programs, RetroArch and Godot ignore a "change", so re-announce it.
        rm -f "$RG351P_PADPROXY_RULE"
        udevadm control --reload 2>/dev/null
        udevadm trigger --action=change --subsystem-match=input 2>/dev/null
        for _d in /sys/class/input/event*; do
            _n=""
            read -r _n 2>/dev/null < "$_d/device/name"
            [ "$_n" = "$RG351P_PAD_NAME" ] && udevadm trigger --action=add "$_d" 2>/dev/null
        done
        echo "padproxy gave up; real pad re-announced" >> "$RG351P_PADPROXY_LOG"
        rm -f "$RG351P_PADPROXY_PID"
        _rg351p_padproxy_follow 0
    ) </dev/null >/dev/null 2>&1 &
    echo $! > "$RG351P_PADPROXY_PID"
    log_message "$PLATFORM: pad proxy started"
}

# The pad's event node: the proxy's virtual one when it exists, else the real.
_rg351p_find_pad_node() {
    _rg351p_real=""
    for _rg351p_d in /sys/class/input/event*; do
        _rg351p_n=""
        read -r _rg351p_n 2>/dev/null < "$_rg351p_d/device/name"
        [ "$_rg351p_n" = "$RG351P_PAD_NAME" ] || continue
        _rg351p_ph=""
        read -r _rg351p_ph 2>/dev/null < "$_rg351p_d/device/phys"
        if [ "$_rg351p_ph" = "$RG351P_PADPROXY_PHYS" ]; then
            echo "/dev/input/${_rg351p_d##*/}"
            return 0
        fi
        [ -n "$_rg351p_real" ] || _rg351p_real="/dev/input/${_rg351p_d##*/}"
    done
    [ -n "$_rg351p_real" ] && echo "$_rg351p_real"
}

_rg351p_padproxy_node_up() {
    case "$(_rg351p_find_pad_node)" in
        /dev/input/event*) ;;
        *) return 1 ;;
    esac
    for _rg351p_d in /sys/class/input/event*; do
        _rg351p_ph=""
        read -r _rg351p_ph 2>/dev/null < "$_rg351p_d/device/phys"
        [ "$_rg351p_ph" = "$RG351P_PADPROXY_PHYS" ] && return 0
    done
    return 1
}

_rg351p_pad_input_id() {
    _node="$(_rg351p_find_pad_node)"
    [ -n "$_node" ] || return 1
    _id="$(readlink -f "/sys/class/input/${_node##*/}/device" 2>/dev/null)"
    [ -n "$_id" ] || return 1
    echo "${_id##*/}"
}

_rg351p_rearm_bump() {
    _g=""
    read -r _g 2>/dev/null < "$RG351P_REARM_GEN_FILE"
    case "$_g" in ''|*[!0-9]*) _g=0 ;; esac
    _g=$((_g + 1))
    echo "$_g" > "$RG351P_REARM_GEN_FILE"
    echo "$_g"
}

# True when the re-arm for generation $1 must give up.
_rg351p_rearm_stale() {
    _cur=""
    read -r _cur 2>/dev/null < "$RG351P_REARM_GEN_FILE"
    [ "$_cur" != "$1" ] || [ -d /tmp/sleep_helper_started ]
}

# The pad's input device at boot, for _rg351p_rearm_pad_readers to compare to.
if [ ! -s "$RG351P_PAD_INPUT_FILE" ]; then
    _rg351p_pad_input_id > "$RG351P_PAD_INPUT_FILE" 2>/dev/null || rm -f "$RG351P_PAD_INPUT_FILE"
fi
# A re-arm killed while holding the lock would block every later one.
if [ -d "$RG351P_REARM_LOCK" ] && [ -n "$(find /tmp -maxdepth 1 -name "${RG351P_REARM_LOCK##*/}" -type d -mmin +2 2>/dev/null)" ]; then
    rmdir "$RG351P_REARM_LOCK" 2>/dev/null
fi

# dArkMossCommon's, for the one pad name, after waiting up to 10 s for the pad:
# it hangs off a USB hub and may enumerate late at boot, and a watchdog whose
# getevent opens a missing node exits for good. It also records the pad's
# input device for the wake re-arm. device_init calls it at boot, after which
# the one-time config migrations run; the re-arm calls it with "rearm".
resolve_pad_node() {
    _i=0
    while [ "$_i" -lt 40 ]; do
        _rg351p_pad_input_id >/dev/null && break
        sleep 0.25
        _i=$((_i + 1))
    done
    # Boot (not a re-arm): start the proxy before anything opens the pad, and
    # give it up to 15 s to bring up the virtual node, less if it gives up.
    if [ "$1" != "rearm" ] && _rg351p_padproxy_start; then
        _i=0
        while [ "$_i" -lt 60 ] && ! _rg351p_padproxy_node_up && _rg351p_padproxy_alive; do
            sleep 0.25
            _i=$((_i + 1))
        done
        if _rg351p_padproxy_node_up; then
            # The node exists before udevd has tagged it a joystick (and the
            # real pad is already hidden); let the proxy's udev events finish.
            udevadm settle -t 3 2>/dev/null
        else
            # Readers started now get the real pad, which the proxy grabs once
            # it is up: move them to the virtual pad when it appears.
            log_message "$PLATFORM: pad proxy has no virtual pad yet, using the real one"
            _rg351p_padproxy_follow 60 </dev/null >/dev/null 2>&1 &
        fi
    fi
    _pad="$(_rg351p_find_pad_node)"
    if [ -n "$_pad" ]; then
        export EVENT_PATH_READ_INPUTS_SPRUCE="$_pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$_pad"
        export EVENT_PATH_SEND_TO_DRASTIC="$_pad"
        log_message "$PLATFORM: joypad at $_pad"
        _rg351p_pad_input_id > "$RG351P_PAD_INPUT_FILE" 2>/dev/null || rm -f "$RG351P_PAD_INPUT_FILE"
    else
        log_message "$PLATFORM: no joypad node found - controls will be dead"
    fi
    if [ "$1" != "rearm" ] && [ ! -f "$RG351P_MIGRATE2_FLAG" ]; then
        _rg351p_migrate_v2
    fi
    if [ "$1" != "rearm" ] && [ ! -f "$RG351P_MIGRATE_FLAG" ]; then
        _rg351p_migrate_v1
    fi
}

_rg351p_rearm_pad_readers() {
    _gen="$1"

    # Let sleep_helper.sh finish first (its idle_watchdog.sh start included).
    # Its directory still being there is this wake's sleep_helper being slow
    # (a hung bluealsad, aplay): a new sleep can only begin after it is
    # removed, and every later wake bumps the generation. So wait on it, up
    # to 60 s, and give up early only for a newer wake.
    _w=0
    while [ -d /tmp/sleep_helper_started ] && [ "$_w" -lt 240 ]; do
        [ "$(cat "$RG351P_REARM_GEN_FILE" 2>/dev/null)" = "$_gen" ] || return 0
        sleep 0.25
        _w=$((_w + 1))
    done
    if [ -d /tmp/sleep_helper_started ]; then
        log_message "$PLATFORM: sleep_helper still running 60 s after wake, pad readers not restarted"
        return 0
    fi
    sleep 0.3
    _rg351p_rearm_stale "$_gen" && return 0

    # With the readers already on the proxy's virtual pad, which never left,
    # nothing moved. Readers started on the real (grabbed) pad after a slow
    # proxy at boot, or left on a virtual pad a proxy restart destroyed, are
    # recorded under another input device: the loop below then breaks at once
    # and they are restarted on the current node.
    _rec=""
    read -r _rec 2>/dev/null < "$RG351P_PAD_INPUT_FILE"
    if _rg351p_padproxy_node_up && [ -n "$_rec" ] && [ "$(_rg351p_pad_input_id)" = "$_rec" ]; then
        log_message "$PLATFORM: pad proxy kept the controls across the sleep"
        return 0
    fi

    _before=""
    read -r _before 2>/dev/null < "$RG351P_PAD_INPUT_FILE"
    _now=""
    _i=0
    while [ "$_i" -lt 40 ]; do
        _rg351p_rearm_stale "$_gen" && return 0
        _now="$(_rg351p_pad_input_id)"
        [ -n "$_now" ] && [ "$_now" != "$_before" ] && break
        sleep 0.25
        _i=$((_i + 1))
    done
    if [ -z "$_now" ]; then
        _i=0
        while [ -z "$_now" ] && [ "$_i" -lt 50 ]; do
            sleep 1
            _rg351p_rearm_stale "$_gen" && return 0
            _now="$(_rg351p_pad_input_id)"
            _i=$((_i + 1))
        done
        if [ -z "$_now" ]; then
            log_message "$PLATFORM: pad missing 60 s after wake, pad readers not restarted"
            return 0
        fi
    fi
    if [ "$_now" != "$_before" ]; then
        log_message "$PLATFORM: pad came back as $_now (was ${_before:-unknown}) after wake, restarting the pad readers"
    else
        log_message "$PLATFORM: pad still $_now after wake, restarting the pad readers anyway"
    fi
    sleep 0.5    # let udev finish the new node before the readers open it
    _rg351p_rearm_stale "$_gen" && return 0

    # A newer re-arm can only find the lock held by an older one that passed
    # its last check just before; wait for it rather than skip, so the pad
    # readers this wake needs are started on the current node.
    _w=0
    until mkdir "$RG351P_REARM_LOCK" 2>/dev/null; do
        if [ "$_w" -ge 20 ]; then
            log_message "$PLATFORM: pad re-arm lock still held after 5 s, pad readers not restarted"
            return 0
        fi
        sleep 0.25
        _w=$((_w + 1))
        _rg351p_rearm_stale "$_gen" && return 0
    done
    echo "$_now" > "$RG351P_PAD_INPUT_FILE"
    resolve_pad_node rearm
    resolve_key_event_node
    # Clear hold state the killed menu reader may leave, and drop the idlemons
    # still reading the old node: restart_pad_readers starts idle_watchdog.sh,
    # which starts them afresh.
    rm -f /tmp/menubtn /tmp/menubtn_cancelled
    killall -q idlemon 2>/dev/null
    restart_pad_readers
    rmdir "$RG351P_REARM_LOCK" 2>/dev/null
}

# dArkMossCommon.sh's device_enter_sleep; keep it in sync. It first records
# bl_power: suspend and resume power the panel down and up again, so after the
# wake bl_power no longer says whether Songo had blanked it.
device_enter_sleep() {
    cat /sys/class/backlight/backlight/bl_power > /tmp/rg351p_blp_sleep 2>/dev/null
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    # The base's sleep hook restores the brightness it saw before suspend, and
    # resume thaws the game: a timed wake would light the panel and run the game
    # until save_poweroff closes it. Only a manual wake restores both.
    signal_emulators STOP
    echo 0 > "$DEVICE_BACKLIGHT_PATH"
    trigger_device_sleep
}

device_exit_sleep() {
    _blp="$(cat /tmp/rg351p_blp_sleep 2>/dev/null)"
    rm -f /tmp/rg351p_blp_sleep
    darkmoss_exit_sleep
    # Songo#5's own screen-off (TYPE2 set_brightness 0) sets only bl_power=1,
    # which apply_backlight clears: the panel would light under a Songo that
    # still thinks it is dark. Leave it dark; Songo's own wake relights it.
    if [ "$_blp" = 1 ] && pgrep -x sbc_4_3_rcv12 >/dev/null 2>&1; then
        echo 1 > /sys/class/backlight/backlight/bl_power 2>/dev/null
    fi
    _rg351p_motor_safe_off
    _gen="$(_rg351p_rearm_bump)"
    _rg351p_rearm_pad_readers "$_gen" </dev/null >/dev/null 2>&1 &
}

# RetroArch's udev numbering of this pad (RG351P.cfg): Select 22, B 16, X 17,
# Y 18, L1 19, R1 20, R2 26.
set_default_ra_hotkeys() {
    RA_FILE="$(platform_path "/mnt/SDCARD/Saves/ra-configs/retroarch-%s.cfg")"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"22\"" \
        "input_exit_emulator_btn = \"16\"" \
        "input_fps_toggle_btn = \"17\"" \
        "input_load_state_btn = \"19\"" \
        "input_save_state_btn = \"20\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"18\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"26\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}

# The stick click that is spruce's menu button (B_MENU, RG351P.cfg) must not
# also press L3/R3 in the game: player 1's L3/R3 binds follow the Menu button
# setting at every launch (the pad's autoconfig leaves both clicks unbound, so
# a "nul" here is no bind at all). Only written when they differ. The rest is
# dArkMossCommon.sh's setup_for_retroarch; keep it in sync.
setup_for_retroarch() {
    _rg351p_racfg="$(platform_path "/mnt/SDCARD/Saves/ra-configs/retroarch-%s.cfg")"
    if [ "$B_MENU" = "1 313" ]; then
        _rg351p_l3='input_player1_l3_btn = "23"'
        _rg351p_r3='input_player1_r3_btn = "nul"'
    else
        _rg351p_l3='input_player1_l3_btn = "nul"'
        _rg351p_r3='input_player1_r3_btn = "24"'
    fi
    if [ -f "$_rg351p_racfg" ] &&
        ! { grep -qxF "$_rg351p_l3" "$_rg351p_racfg" && grep -qxF "$_rg351p_r3" "$_rg351p_racfg"; }; then
        update_ra_config_file_with_new_setting "$_rg351p_racfg" "$_rg351p_l3" "$_rg351p_r3" >/dev/null
    fi
    unset _rg351p_racfg _rg351p_l3 _rg351p_r3

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

# One-time fix-ups of settings an earlier RG351P build left on the card, which
# a new default alone does not reach (each live copy is seeded only when it is
# missing). Run from device_init (resolve_pad_node), when every helper is
# defined and before any emulator starts. A lock directory keeps two runs
# apart; the flag is only set once every step is done, so a step that could
# not run yet is tried again at the next boot.
# v5: PPSSPP fix-ups a new default alone does not reach (live copies are only
# seeded when missing):
# - UIScaleFactor: the V10's -1 overflows the 480x320 panel (pause menu items
#   overlap), and -4 and -6 still did; only an untouched old value changes.
# - controls: a live copy that still puts PSP L/R on pad buttons 7/8
#   (10-194/10-195, an older layout) has them on the wrong buttons; this pad's
#   L1/R1 are 10-193/10-192. Reset to the default.
RG351P_MIGRATE2_FLAG="/mnt/SDCARD/Saves/flags/.rg351p_migrate_v5"
_rg351p_migrate_v2() {
    _m2dir="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
    _m2live="$_m2dir/ppsspp-RG351P.ini"
    if [ -f "$_m2live" ] && grep -Eqx 'UIScaleFactor = -(1|4|6)' "$_m2live"; then
        sed -E 's/^UIScaleFactor = -(1|4|6)$/UIScaleFactor = -8/' "$_m2live" > "$_m2live.tmp" 2>/dev/null &&
            [ -s "$_m2live.tmp" ] && mv -f "$_m2live.tmp" "$_m2live" &&
            log_message "$PLATFORM: PPSSPP UI scale lowered to fit the screen (one-time fix)" ||
            { rm -f "$_m2live.tmp"; return 0; }
    fi
    _m2ctl="$_m2dir/controls-RG351P.ini"
    _m2def="/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM/controls-RG351P.ini"
    if [ -f "$_m2ctl" ] && [ -f "$_m2def" ] &&
        grep -Eq '^(L = .*10-194|R = .*10-195)([,:]|$)' "$_m2ctl"; then
        cp -f "$_m2def" "$_m2ctl" &&
            log_message "$PLATFORM: PPSSPP controls reset to the default, L/R were on buttons 7/8 (one-time fix)" ||
            return 0
    fi
    mkdir -p "${RG351P_MIGRATE2_FLAG%/*}" && touch "$RG351P_MIGRATE2_FLAG"
}

RG351P_MIGRATE_FLAG="/mnt/SDCARD/Saves/flags/.rg351p_migrate_v1"
RG351P_OLD_PPSSPP_L='L = 1-45,10-192,10-194'
_rg351p_migrate_v1() {
    mkdir /tmp/rg351p_migrate.lock 2>/dev/null || return 0
    _mok=1

    # RetroArch: the left stick reports inverted on both axes, which the old
    # shipped binds did not account for (only the untouched old values are
    # changed); and a config saved with SDL's 0-14 button numbering instead of
    # RetroArch's udev numbering (15-26, d-pad on hat 0) has every button and
    # hotkey dead.
    _mcfg="$(platform_path "/mnt/SDCARD/Saves/ra-configs/retroarch-%s.cfg")"
    if [ -f "$_mcfg" ]; then
        if grep -q '^input_player1_l_x_plus_axis = "+0"$' "$_mcfg"; then
            update_ra_config_file_with_new_setting "$_mcfg" \
                'input_player1_l_x_minus_axis = "+0"' \
                'input_player1_l_x_plus_axis = "-0"' \
                'input_player1_l_y_minus_axis = "+1"' \
                'input_player1_l_y_plus_axis = "-1"'
            log_message "$PLATFORM: RetroArch left stick binds inverted (one-time fix)"
        fi
        if grep -Eq '^input_player1_(a|b|x|y|l|r|l2|r2|l3|r3|start|select)_btn = "([0-9]|1[0-4])"$' "$_mcfg"; then
            update_ra_config_file_with_new_setting "$_mcfg" \
                'input_player1_a_btn = "15"' \
                'input_player1_b_btn = "16"' \
                'input_player1_x_btn = "17"' \
                'input_player1_y_btn = "18"' \
                'input_player1_l_btn = "19"' \
                'input_player1_r_btn = "20"' \
                'input_player1_start_btn = "21"' \
                'input_player1_select_btn = "22"' \
                'input_player1_l3_btn = "23"' \
                'input_player1_r3_btn = "24"' \
                'input_player1_l2_btn = "25"' \
                'input_player1_r2_btn = "26"' \
                'input_player1_up_btn = "h0up"' \
                'input_player1_down_btn = "h0down"' \
                'input_player1_left_btn = "h0left"' \
                'input_player1_right_btn = "h0right"'
            set_default_ra_hotkeys
            log_message "$PLATFORM: RetroArch binds moved to the udev numbering (one-time fix)"
        fi
    fi

    # PPSSPP: the live controls copy of the old layout (a copy of the V10's,
    # which does not fit this pad's positional SDL map) gets the new default.
    # Only once the default itself is the new one.
    _mlive="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/controls-RG351P.ini"
    _mdef="/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM/controls-RG351P.ini"
    if [ -f "$_mlive" ] && grep -qxF "$RG351P_OLD_PPSSPP_L" "$_mlive"; then
        if [ -f "$_mdef" ] && ! grep -qxF "$RG351P_OLD_PPSSPP_L" "$_mdef"; then
            cp -f "$_mdef" "$_mlive" && log_message "$PLATFORM: PPSSPP controls reset to the new default (one-time fix)"
        else
            _mok=0
        fi
    fi

    # spruce-config.json: the RG351P overlay no longer carries Saves/, so a
    # spruce that predates the RG351P lacks it in the Menu button setting's
    # devices. Only an existing setting is touched, and through a temp file so
    # a failed write cannot truncate the settings store.
    _msc="/mnt/SDCARD/Saves/spruce/spruce-config.json"
    if [ -f "$_msc" ]; then
        if jq -e '.menuOptions."Button Settings".menuButton | type == "object"' "$_msc" >/dev/null 2>&1 &&
            ! jq -e '.menuOptions."Button Settings".menuButton.devices | index("ANBERNIC_RG351P")' "$_msc" >/dev/null 2>&1; then
            if jq '.menuOptions."Button Settings".menuButton.devices |= ((. // []) | if index("ANBERNIC_RG351P") then . else . + ["ANBERNIC_RG351P"] end)' \
                "$_msc" > "$_msc.tmp" 2>/dev/null && [ -s "$_msc.tmp" ] && mv -f "$_msc.tmp" "$_msc"; then
                log_message "$PLATFORM: added the RG351P to the Menu button setting (one-time fix)"
            else
                rm -f "$_msc.tmp"
                _mok=0
            fi
        fi
    else
        _mok=0
    fi

    if [ "$_mok" = 1 ]; then
        mkdir -p "${RG351P_MIGRATE_FLAG%/*}" && touch "$RG351P_MIGRATE_FLAG"
    fi
    rmdir /tmp/rg351p_migrate.lock 2>/dev/null
}
