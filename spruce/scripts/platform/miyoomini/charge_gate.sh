#!/bin/sh
# Charge screen for a Mini Flip that a charger switched on. miyoo_mini_startup.sh runs this before keymon and
# the rest of the boot; it returns to let the boot continue, or powers the unit off, which keeps it charging.
#
# The AXP223 sets register 0x00 bit 0 when inserting the charger is what powered the unit on, and clears it after a
# power-key start, cable or not; pwrkeyval reads 0 either way on this model. Bits 7 and 5 are the ACIN and VBUS
# inputs, so "charger still in" is either of them. Register 0xb9 bits 0-6 are the battery percentage.
#
#   POWER held for CG_HOLD_SECS                   continue booting, with the boot screen put back as it was found
#   POWER pressed and let go                      restart the idle countdown
#   lid closed, charger pulled, or CG_IDLE_TICKS  power off
#
# Opt-in for now: only with spruce/flags/charge_gate present. The gate checks for what it needs rather than for a
# model: a readable AXP223 and a 752x560 framebuffer are only on the Mini Flip. Anything missing or unexpected means
# the boot continues as if this script did not exist.

CG_SD=/mnt/SDCARD
CG_AXP_READ="$CG_SD/spruce/miyoomini/bin/axp_read"
CG_GETEVENT="$CG_SD/spruce/miyoomini/bin/getevent"
CG_FRAMES="$CG_SD/spruce/miyoomini/charge"
CG_FLAG="$CG_SD/spruce/flags/charge_gate"
CG_LOG="$CG_SD/Saves/spruce/charge_gate.log"
CG_STATE=/tmp/charge_gate
CG_KEYS=/dev/input/event0
CG_FB=/dev/fb0
CG_FB_SYS=/sys/class/graphics/fb0
# The same nodes as device_functions/MiyooMini.sh, which only helperFunctions.sh may source and which is not
# loaded this early
CG_LID=/sys/devices/soc0/soc/soc:hall-mh248/hallvalue
CG_BACKLIGHT=/sys/devices/soc0/soc/1f003400.pwm/pwm/pwmchip0/pwm0/duty_cycle
CG_GUI=/proc/mi_modules/fb/mi_fb0

# The frames are built for this framebuffer shape by miyoomini/make_charge_frames.py in spruceSource, which also
# holds axp_read's source
CG_WIDTH=752
CG_HEIGHT=560
CG_STRIDE=3008
CG_FRAME_COUNT=5
CG_FRAME_USEC=300000
CG_HOLD_SECS=1
CG_RELEASE_TICKS=3
CG_IDLE_TICKS=15
CG_LEVEL_TICKS=10
CG_DEFAULT_BACKLIGHT=100
CG_POWEROFF_WAIT=30

CG_OUTCOME=""
CG_IDLE=0
CG_KEY_DOWN=0
CG_HOLD_PID=""
CG_PAN_Y=0

cg_log() {
    echo "$(cut -d' ' -f1 /proc/uptime 2>/dev/null) $*" 2>/dev/null >> "$CG_LOG"
}

# Prints one register as 0xNN; fails when the reader is missing or the bus read fails
cg_reg() {
    _v="$("$CG_AXP_READ" "$1" 2>/dev/null)" || return 1
    case "$_v" in
        0x[0-9a-f][0-9a-f]) echo "$_v" ;;
        *) return 1 ;;
    esac
}

cg_charger_started() {
    _v="$(cg_reg 0x00)" || return 1
    [ $((_v & 0x01)) -ne 0 ] && [ $((_v & 0xa0)) -ne 0 ]
}

# An unreadable register counts as present: a false "unplugged" would power off a unit that is charging,
# while the idle countdown bounds the other mistake
cg_charger_present() {
    _v="$(cg_reg 0x00)" || return 0
    [ $((_v & 0xa0)) -ne 0 ]
}

cg_lid_open() {
    [ -r "$CG_LID" ] || return 0
    read -r _lid 2>/dev/null < "$CG_LID" || return 0
    [ "${_lid%"${_lid#?}"}" != "0" ]
}

# Sets CG_PAN_Y to the visible page; fails unless the framebuffer has the shape the frames were built for
cg_fb_ready() {
    read -r _size 2>/dev/null < "$CG_FB_SYS/virtual_size" || return 1
    read -r _stride 2>/dev/null < "$CG_FB_SYS/stride" || return 1
    read -r _pan 2>/dev/null < "$CG_FB_SYS/pan" || return 1
    [ "${_size%%,*}" = "$CG_WIDTH" ] && [ "$_stride" = "$CG_STRIDE" ] || return 1
    CG_PAN_Y="${_pan#*,}"
    case "$CG_PAN_Y" in ''|*[!0-9]*) return 1 ;; esac
    [ $(( ${_size#*,} - CG_PAN_Y )) -ge "$CG_HEIGHT" ]
}

# Sets CG_BAND_TOP and CG_BAND_ROWS; fails unless band.txt describes rows inside the screen
cg_band_ready() {
    read -r CG_BAND_TOP CG_BAND_ROWS 2>/dev/null < "$CG_FRAMES/band.txt" || return 1
    case "$CG_BAND_TOP:$CG_BAND_ROWS" in *[!0-9:]*|:*|*:) return 1 ;; esac
    [ "$CG_BAND_ROWS" -gt 0 ] && [ $((CG_BAND_TOP + CG_BAND_ROWS)) -le "$CG_HEIGHT" ] || return 1
    _n=1
    while [ "$_n" -le "$CG_FRAME_COUNT" ]; do
        [ -r "$CG_FRAMES/frame-$_n.raw.gz" ] || return 1
        _n=$((_n + 1))
    done
}

# The first frame to show: the vendor's levels, at 25, 50, 75 and 99 percent
cg_level_frame() {
    _v="$(cg_reg 0xb9)" || { echo 1; return; }
    _pct=$((_v & 0x7f))
    if [ "$_pct" -ge 99 ]; then echo 5
    elif [ "$_pct" -ge 75 ]; then echo 4
    elif [ "$_pct" -ge 50 ]; then echo 3
    elif [ "$_pct" -ge 25 ]; then echo 2
    else echo 1
    fi
}

cg_clear() {
    dd if=/dev/zero of="$CG_FB" bs="$CG_STRIDE" seek="$CG_PAN_Y" count="$CG_HEIGHT" conv=notrunc 2>/dev/null
}

# The boot screen the gate covers, so a boot it lets through looks like one it never touched
cg_save_screen() {
    dd if="$CG_FB" of="$CG_STATE/screen" bs="$CG_STRIDE" skip="$CG_PAN_Y" count="$CG_HEIGHT" 2>/dev/null
}

cg_restore_screen() {
    [ -s "$CG_STATE/screen" ] || { cg_clear; return; }
    dd if="$CG_STATE/screen" of="$CG_FB" bs="$CG_STRIDE" seek="$CG_PAN_Y" conv=notrunc 2>/dev/null
}

cg_draw() {
    zcat "$CG_FRAMES/frame-$1.raw.gz" |
        dd of="$CG_FB" bs="$CG_STRIDE" seek=$((CG_PAN_Y + CG_BAND_TOP)) conv=notrunc 2>/dev/null
}

cg_screen() {
    if [ "$1" = "on" ]; then
        echo "GUI_SHOW 0 on" 2>/dev/null > "$CG_GUI"
        echo "$CG_BRIGHTNESS" 2>/dev/null > "$CG_BACKLIGHT"
    else
        echo "0" 2>/dev/null > "$CG_BACKLIGHT"
        echo "GUI_SHOW 0 off" 2>/dev/null > "$CG_GUI"
    fi
}

cg_start_hold_timer() {
    ( sleep "$CG_HOLD_SECS"; echo "hold" ) >&4 &
    CG_HOLD_PID=$!
}

cg_cancel_hold_timer() {
    [ -n "$CG_HOLD_PID" ] && kill "$CG_HOLD_PID" 2>/dev/null
    CG_HOLD_PID=""
}

# The state machine: one event in, CG_OUTCOME set to "boot" or "off" when the gate is done
cg_on_event() {
    case "$1" in
        key)
            CG_IDLE=0
            case "$2" in
                1) CG_KEY_DOWN=1; cg_cancel_hold_timer; cg_start_hold_timer ;;
                0) CG_KEY_DOWN=0; cg_cancel_hold_timer ;;
            esac
            ;;
        hold)
            cg_log "POWER held: continuing the boot"
            CG_OUTCOME=boot
            ;;
        tick)
            if ! cg_charger_present; then
                cg_log "charger removed: powering off"
                CG_OUTCOME=off
                return
            fi
            if ! cg_lid_open; then
                cg_log "lid closed: powering off"
                CG_OUTCOME=off
                return
            fi
            CG_IDLE=$((CG_IDLE + 1))
            if [ "$CG_IDLE" -ge "$CG_IDLE_TICKS" ]; then
                cg_log "idle: powering off"
                CG_OUTCOME=off
            elif [ $((CG_IDLE % CG_LEVEL_TICKS)) -eq 0 ]; then
                cg_level_frame > "$CG_STATE/start"
            fi
            ;;
    esac
}

# spruce's getevent runs evtest and prints mapped names, "key B_POWER 1" on press and "key B_POWER 0" on release;
# it reports no repeats
cg_key_lines() {
    while read -r _line; do
        case "$_line" in
            "key B_POWER 1") echo "key 1" ;;
            "key B_POWER 0") echo "key 0" ;;
        esac
    done
}

cg_start_frame() {
    _start="$(cat "$CG_STATE/start" 2>/dev/null)"
    case "$_start" in ''|*[!0-9]*) _start=1 ;; esac
    [ "$_start" -ge 1 ] && [ "$_start" -le "$CG_FRAME_COUNT" ] || _start=1
    echo "$_start"
}

# Stops at the stop file rather than by signal, so a draw is never cut off half way and never lands after the
# screen is put back
cg_animate() {
    _frame="$(cg_start_frame)"
    while [ ! -e "$CG_STATE/stop" ]; do
        cg_draw "$_frame"
        usleep "$CG_FRAME_USEC"
        _frame=$((_frame + 1))
        [ "$_frame" -gt "$CG_FRAME_COUNT" ] && _frame="$(cg_start_frame)"
    done
}

# The hold fires with POWER still down. keymon and the frontend start next and read a release on its own as a
# press, so the gate takes the release itself
cg_wait_for_release() {
    _ticks=0
    while [ "$CG_KEY_DOWN" = 1 ] && [ "$_ticks" -lt "$CG_RELEASE_TICKS" ] && read -r _kind _arg <&4; do
        case "$_kind $_arg" in
            "key 0") CG_KEY_DOWN=0 ;;
            "tick "*) _ticks=$((_ticks + 1)) ;;
        esac
    done
    if [ "$CG_KEY_DOWN" = 1 ]; then
        cg_log "POWER still down after $CG_RELEASE_TICKS s: continuing anyway"
    else
        cg_log "POWER released"
    fi
}

# Kills a process and everything under it: getevent leaves its evtest behind otherwise, holding the key device
cg_kill_tree() {
    for _stat in /proc/[0-9]*/stat; do
        read -r _pid _comm _state _ppid _rest 2>/dev/null < "$_stat" || continue
        [ "$_ppid" = "$1" ] && cg_kill_tree "$_pid"
    done
    kill "$1" 2>/dev/null
}

cg_power_off() {
    cg_screen off
    sync
    poweroff
    # poweroff only asks init; if the unit is still up after this, let it boot rather than hang dark
    sleep "$CG_POWEROFF_WAIT"
    cg_log "still running after poweroff: continuing the boot"
}

cg_run() {
    rm -rf "$CG_STATE"
    mkdir -p "$CG_STATE" || return 0
    mkfifo "$CG_STATE/events" || return 0
    exec 4<>"$CG_STATE/events"

    read -r CG_BRIGHTNESS 2>/dev/null < "$CG_BACKLIGHT"
    CG_SAVED_BRIGHTNESS="${CG_BRIGHTNESS:-0}"
    [ "${CG_BRIGHTNESS:-0}" -gt 0 ] 2>/dev/null || CG_BRIGHTNESS="$CG_DEFAULT_BACKLIGHT"

    cg_level_frame > "$CG_STATE/start"
    cg_save_screen
    cg_clear
    cg_screen on

    # Its own FIFO rather than a pipe, so $! is getevent itself and the cleanup can reach its evtest
    mkfifo "$CG_STATE/keys" || return 0
    "$CG_GETEVENT" "$CG_KEYS" 2>/dev/null > "$CG_STATE/keys" &
    _getevent=$!
    cg_key_lines < "$CG_STATE/keys" >&4 &
    _reader=$!
    ( while :; do sleep 1; echo "tick"; done ) >&4 &
    _ticker=$!
    cg_animate &
    _animator=$!

    while [ -z "$CG_OUTCOME" ] && read -r _kind _arg <&4; do
        cg_on_event "$_kind" "$_arg"
    done

    cg_cancel_hold_timer
    touch "$CG_STATE/stop"
    wait "$_animator" 2>/dev/null

    # A boot continues as one the gate never touched: its boot screen back, the panel shown, and lit. A backlight
    # found at 0 keeps the gate's level, or the panel goes dark until the frontend sets one
    [ "$CG_SAVED_BRIGHTNESS" -gt 0 ] 2>/dev/null && CG_BRIGHTNESS="$CG_SAVED_BRIGHTNESS"
    if [ "$CG_OUTCOME" = "boot" ]; then
        cg_restore_screen
        cg_screen on
        cg_wait_for_release
    fi

    kill "$_ticker" 2>/dev/null
    wait "$_ticker" 2>/dev/null
    cg_kill_tree "$_getevent"
    wait "$_getevent" "$_reader" 2>/dev/null
    exec 4>&-

    if [ "$CG_OUTCOME" = "off" ]; then
        cg_clear
        cg_power_off
        # Still up: boot as above
        cg_restore_screen
        cg_screen on
    fi
    rm -rf "$CG_STATE"
}

cg_main() {
    [ -f "$CG_FLAG" ] || return 0
    cg_charger_started || return 0
    cg_band_ready || return 0
    cg_fb_ready || return 0
    # Keeps the previous run: switching a unit back on with the charger is itself a charge-screen boot.
    # printf, not ":": a failed redirection on a special builtin would end the script
    mv -f "$CG_LOG" "${CG_LOG%.log}.1.log" 2>/dev/null
    printf '' 2>/dev/null > "$CG_LOG"
    cg_log "charger-started boot: charge screen"
    cg_run
}

cg_main
