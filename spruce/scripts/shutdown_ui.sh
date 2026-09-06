#!/bin/sh

# Shutdown-time UI that works with the card gone (SPR-MED-198, SPR-MED-199).
#
# Sourced twice: from the card by save_poweroff.sh or the USB Storage Mode app
# to STAGE it into SHUTDOWN_UI_DIR, and from that /tmp copy by stage 2 to USE
# it once the card is unmounted. Nothing here runs on load. Every runtime
# dependency is on the rootfs or in SHUTDOWN_UI_DIR: the display tool and the
# input reader (the repairSD.sh pattern), the rootfs SDL libraries, a font, a
# background, fsck.fat, and an env file with the platform facts stage 2 can no
# longer source.
SHUTDOWN_UI_DIR="${SHUTDOWN_UI_DIR:-/tmp/shutdown_ui}"

shutdown_ui_log() {
    echo "shutdown ui [$(cut -d' ' -f1 /proc/uptime 2>/dev/null)s]: $1"
}

# Rootfs-only library path: the platform cfg's LD_LIBRARY_PATH without the
# card entries (the same table repairSD.sh hand-codes per platform).
shutdown_ui_rootfs_ld_path() {
    _out=""
    _old_ifs="$IFS"; IFS=:
    for _d in $LD_LIBRARY_PATH; do
        case "$_d" in ""|/mnt/SDCARD*|/mnt/sdcard*) continue ;; esac
        _out="${_out:+$_out:}$_d"
    done
    IFS="$_old_ifs"
    echo "${_out:-/usr/lib:/lib}"
}

# Card side. Copy what the UI needs into SHUTDOWN_UI_DIR and record the
# platform facts. Returns 1 if anything required is missing; fsck.fat is
# optional (without it a dirty card is reported, not repaired).
shutdown_ui_stage() {
    _bin=/mnt/SDCARD/spruce/bin64
    [ "$PLATFORM_ARCHITECTURE" = "armhf" ] && _bin=/mnt/SDCARD/spruce/bin
    _font=/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf
    _bg=/mnt/SDCARD/spruce/imgs/bg_tree.png
    [ "${DISPLAY_WIDTH:-0}" -ge 1280 ] && _bg=/mnt/SDCARD/spruce/imgs/bg_tree_wide.png
    rm -rf "$SHUTDOWN_UI_DIR"
    mkdir -p "$SHUTDOWN_UI_DIR" || return 1
    for _f in "$_bin/display_text.elf" "$_bin/getevent" "$_font" "$_bg" /mnt/SDCARD/spruce/scripts/shutdown_ui.sh; do
        if [ ! -f "$_f" ]; then
            log_message "shutdown ui: cannot stage, missing $_f"
            return 1
        fi
    done
    cp "$_bin/display_text.elf" "$SHUTDOWN_UI_DIR/display_text.elf" &&
    cp "$_bin/getevent" "$SHUTDOWN_UI_DIR/getevent" &&
    cp "$_font" "$SHUTDOWN_UI_DIR/font.ttf" &&
    cp "$_bg" "$SHUTDOWN_UI_DIR/bg.png" &&
    cp /mnt/SDCARD/spruce/scripts/shutdown_ui.sh "$SHUTDOWN_UI_DIR/shutdown_ui.sh" || return 1
    [ -f "$_bin/fsck.fat" ] && cp "$_bin/fsck.fat" "$SHUTDOWN_UI_DIR/fsck.fat" && chmod +x "$SHUTDOWN_UI_DIR/fsck.fat"
    chmod +x "$SHUTDOWN_UI_DIR/display_text.elf" "$SHUTDOWN_UI_DIR/getevent"
    {
        echo "PLATFORM='$PLATFORM'"
        echo "SD_DEV='$SD_DEV'"
        echo "SD_MOUNTPOINT='$SD_MOUNTPOINT'"
        echo "BATTERY='$BATTERY'"
        echo "EVENT_PATH_READ_INPUTS_SPRUCE='$EVENT_PATH_READ_INPUTS_SPRUCE'"
        echo "B_A='$B_A'"
        echo "B_B='$B_B'"
        echo "DISPLAY_WIDTH='${DISPLAY_WIDTH:-640}'"
        echo "DISPLAY_HEIGHT='${DISPLAY_HEIGHT:-480}'"
        echo "DISPLAY_ROTATION='${DISPLAY_ROTATION:-0}'"
        echo "SHUTDOWN_UI_LD_LIBRARY_PATH='$(shutdown_ui_rootfs_ld_path)'"
    } > "$SHUTDOWN_UI_DIR/env" || return 1
    sync
    log_message "shutdown ui: staged in $SHUTDOWN_UI_DIR"
    return 0
}

# /tmp side.
shutdown_ui_load_env() {
    [ -f "$SHUTDOWN_UI_DIR/env" ] || return 1
    . "$SHUTDOWN_UI_DIR/env"
}

shutdown_ui_display() {
    shutdown_ui_display_kill
    _text_width=$((DISPLAY_WIDTH - 80))
    LD_LIBRARY_PATH="$SHUTDOWN_UI_LD_LIBRARY_PATH" "$SHUTDOWN_UI_DIR/display_text.elf" \
        "$DISPLAY_WIDTH" "$DISPLAY_HEIGHT" "$DISPLAY_ROTATION" "$SHUTDOWN_UI_DIR/bg.png" "$1" \
        0 30 50 middle "$_text_width" eb db b2 "$SHUTDOWN_UI_DIR/font.ttf" 7f 7f 7f 0 1.0 \
        >>"$SHUTDOWN_UI_DIR/display.out" 2>&1 &
    SHUTDOWN_UI_DISPLAY_PID=$!
    sleep 0.5
    if kill -0 "$SHUTDOWN_UI_DISPLAY_PID" 2>/dev/null; then
        shutdown_ui_log "display up (pid $SHUTDOWN_UI_DISPLAY_PID): $1"
    else
        shutdown_ui_log "display EXITED at once: $1 - $(tail -1 "$SHUTDOWN_UI_DIR/display.out" 2>/dev/null)"
    fi
}

shutdown_ui_display_kill() {
    [ -n "$SHUTDOWN_UI_DISPLAY_PID" ] && kill "$SHUTDOWN_UI_DISPLAY_PID" 2>/dev/null
    SHUTDOWN_UI_DISPLAY_PID=""
}

shutdown_ui_display_errors() {
    [ -s "$SHUTDOWN_UI_DIR/display.out" ] && sed 's/^/shutdown ui: display: /' "$SHUTDOWN_UI_DIR/display.out" | tail -6
}

# Input: a getevent on the pad, consulted with shutdown_ui_key_seen A|B.
shutdown_ui_getevent_start() {
    rm -f "$SHUTDOWN_UI_DIR/ge_out"
    "$SHUTDOWN_UI_DIR/getevent" "$EVENT_PATH_READ_INPUTS_SPRUCE" > "$SHUTDOWN_UI_DIR/ge_out" 2>/dev/null &
    SHUTDOWN_UI_GE_PID=$!
}

shutdown_ui_key_seen() {
    case "$1" in
        A) grep -q "key $B_A" "$SHUTDOWN_UI_DIR/ge_out" 2>/dev/null ;;
        B) grep -q "key $B_B" "$SHUTDOWN_UI_DIR/ge_out" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

shutdown_ui_getevent_stop() {
    [ -n "$SHUTDOWN_UI_GE_PID" ] && kill "$SHUTDOWN_UI_GE_PID" 2>/dev/null
    SHUTDOWN_UI_GE_PID=""
}

# The FAT "not properly unmounted" flag, read straight from the block device
# (boot-sector state byte: offset 65 on FAT32, 37 on FAT12/16; bit 0 = dirty).
# It is what the kernel warns about at mount and what Windows offers to "scan
# and fix". It is STICKY: once set, neither a clean unmount nor a clean eject
# clears it - only fsck does. Prints "clean (0x00)" / "dirty (0x01)".
sd_card_dirty_flag() {
    _type=$(dd if="$SD_DEV" bs=1 skip=82 count=5 2>/dev/null)
    if [ "$_type" = "FAT32" ]; then _off=65; else _off=37; fi
    # No od/hexdump: the TrimUI A133P busybox ships neither (measured
    # 2026-09-06, "od: not found" on the Brick, Brick Pro and Smart Pro). Map
    # the one byte to a digit with tr instead; only bits 0 (dirty) and 1
    # (surface scan) are ever set, so values above 7 do not occur.
    _digit=$(dd if="$SD_DEV" bs=1 skip=$_off count=1 2>/dev/null | tr '\000\001\002\003\004\005\006\007' '01234567')
    case "$_digit" in
        [0-7]) ;;
        *) echo "unreadable"; return ;;
    esac
    if [ $((_digit & 1)) -eq 0 ]; then echo "clean (0x0$_digit)"; else echo "dirty (0x0$_digit)"; fi
}

# fsck.fat -a on the (unmounted, quiesced) card. With a message, a screen is
# drawn for it (the USB session); without one, whatever is on the panel stays
# (PyUI's "Repairing the SD card..." on the shutdown path). Prints the
# outcome; returns fsck's status, 2 when no fsck.fat was staged.
sd_card_repair() {
    if [ ! -x "$SHUTDOWN_UI_DIR/fsck.fat" ]; then
        shutdown_ui_log "no fsck.fat staged, card left as it is"
        return 2
    fi
    [ -n "$1" ] && shutdown_ui_display "$1"
    _t0=$(cut -d' ' -f1 /proc/uptime)
    "$SHUTDOWN_UI_DIR/fsck.fat" -a "$SD_DEV" > "$SHUTDOWN_UI_DIR/fsck.out" 2>&1
    _rc=$?
    shutdown_ui_log "fsck.fat -a rc=$_rc in $(awk -v a="$_t0" -v b="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN{print b-a}') s, flag now: $(sd_card_dirty_flag)"
    tail -3 "$SHUTDOWN_UI_DIR/fsck.out" 2>/dev/null | sed 's/^/shutdown ui: fsck: /'
    return $_rc
}

# The shutdown-path repair (SPR-MED-199). Consent was given in PyUI, which
# owns the question; this only checks that the flag is really set and runs
# the repair. Called by stage 2 after the card's umount SUCCEEDED.
sd_card_repair_if_dirty() {
    _flag="$(sd_card_dirty_flag)"
    shutdown_ui_log "dirty flag after the unmount: $_flag"
    case "$_flag" in
        dirty*) sd_card_repair "" ;;
        *) shutdown_ui_log "card is clean, nothing to repair"; return 0 ;;
    esac
}
