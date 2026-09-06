#!/bin/sh

# Shutdown-time UI that works with the card gone (SPR-MED-198).
#
# Sourced twice: from the card by the USB Storage Mode app to STAGE it into
# SHUTDOWN_UI_DIR, and from that /tmp copy by the USB session inside stage 2
# to USE it once the card is unmounted. Nothing here runs on load. Every runtime
# dependency is on the rootfs or in SHUTDOWN_UI_DIR: the display tool and the
# input reader (the repairSD.sh pattern), the rootfs SDL libraries, a font, a
# background, and an env file with the platform facts stage 2 can no longer
# source.
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
# platform facts. Returns 1 if anything required is missing.
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

