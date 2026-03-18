#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
SYSTEM_EMIT="${SYSTEM_EMIT:-/mnt/SDCARD/spruce/scripts/system-emit}"

start_pyui_message_writer
flag_add "unpacker_ui_visible" --tmp

flag_remove "first_boot_$PLATFORM"
log_message "Starting firstboot script on $PLATFORM"
"$SYSTEM_EMIT" process firstboot "STARTED" "firstboot.sh/startup" "platform=$PLATFORM" || true

WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
UNPACKING_ICON="/mnt/SDCARD/spruce/imgs/refreshing.png"
SPRUCE_LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SPRUCE_VERSION="$(cat "/mnt/SDCARD/spruce/spruce")"
SPLORE_CART="/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore"
UNPACK_STATE_FILE="/mnt/SDCARD/Saves/spruce/unpacker_state"
UNPACK_WAIT_TIMEOUT_SEC=300
FIRSTBOOT_SCREEN_HOLD_FLAG="firstboot_screen_hold"
FIRSTBOOT_FINAL_STATE="COMPLETE"
FIRSTBOOT_FINAL_REASON="normal-exit"
FIRSTBOOT_FINALIZED=0

firstboot_trace_finalize() {
    [ "$FIRSTBOOT_FINALIZED" = "1" ] && return 0
    "$SYSTEM_EMIT" process-finalize firstboot "firstboot.sh" "$FIRSTBOOT_FINAL_STATE" "reason=$FIRSTBOOT_FINAL_REASON platform=$PLATFORM" || true
    FIRSTBOOT_FINALIZED=1
}

cleanup_firstboot_screen_hold() {
    flag_remove "$FIRSTBOOT_SCREEN_HOLD_FLAG"
    firstboot_trace_finalize
}
trap cleanup_firstboot_screen_hold EXIT

"$SYSTEM_EMIT" process-init firstboot "firstboot.sh" "platform=$PLATFORM" || true

read_unpack_state() {
    if [ -f "$UNPACK_STATE_FILE" ]; then
        sed -n 's/^state=//p' "$UNPACK_STATE_FILE" | head -n 1
    else
        echo "idle"
    fi
}

write_unpack_state_failed_resumable() {
    tmp_state="${UNPACK_STATE_FILE}.tmp.$$"
    {
        printf 'state=failed_resumable\n'
        printf 'run_mode=all\n'
        printf 'pid=\n'
        printf 'updated_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'reason=firstboot-timeout\n'
    } > "$tmp_state"
    mv -f "$tmp_state" "$UNPACK_STATE_FILE"
}

show_firstboot_screen() {
    img="$1"
    text="$2"
    duration="${3:-5}"

    flag_add "$FIRSTBOOT_SCREEN_HOLD_FLAG" --tmp
    display_image_and_text "$img" 35 25 "$text" 75
    sleep "$duration"
    flag_remove "$FIRSTBOOT_SCREEN_HOLD_FLAG"
}

show_firstboot_screen "$SPRUCE_LOGO" "Installing spruce $SPRUCE_VERSION" 5

SSH_SERVICE_NAME=$(get_ssh_service_name)
if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
    log_message "Preparing SSH keys if necessary"
    dropbear_generate_keys &
fi

if [ "$DEVICE_SUPPORTS_PORTMASTER" = "true" ]; then
    mkdir -p /mnt/SDCARD/Persistent/
    if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
        extract_7z_with_progress /mnt/SDCARD/App/PortMaster/portmaster.7z /mnt/SDCARD/Persistent/ /mnt/SDCARD/Saves/spruce/portmaster_extract.log "Sprucing up your device"
    else
        show_firstboot_screen "$SPRUCE_LOGO" "Sprucing up your device" 5
    fi

    rm -f /mnt/SDCARD/App/PortMaster/portmaster.7z
fi

# Extract ScummVM standalone binaries (64-bit only)
if [ "$PLATFORM_ARCHITECTURE" != "armhf" ]; then
    SCUMMVM_DIR="/mnt/SDCARD/Emu/SCUMMVM"
    for SCUMMVM_7Z in "$SCUMMVM_DIR"/scummvm_*.7z; do
        [ -f "$SCUMMVM_7Z" ] || continue
        show_firstboot_screen "$SPRUCE_LOGO" "Extracting ScummVM!" 5
        extract_7z_with_progress "$SCUMMVM_7Z" "$SCUMMVM_DIR" /mnt/SDCARD/Saves/spruce/scummvm_extract.log
        rm -f "$SCUMMVM_7Z"
    done
fi

show_firstboot_screen "$WIKI_ICON" "Check out the spruce wiki on our GitHub page for tips and FAQs!" 5

perform_fw_check

if flag_check "pre_menu_unpacking"; then
    "$SYSTEM_EMIT" process firstboot "PREMENU_LOCK_DETECTED" "firstboot.sh/wait_pre_menu" "pre_menu_unpacking lock exists" || true
    show_firstboot_screen "$UNPACKING_ICON" "Finishing up unpacking themes and files.........." 5
    "$SYSTEM_EMIT" process firstboot "WAIT_PRESERVE_SILENT_LOCK" "firstboot.sh/wait_pre_menu" "preserving silentUnpacker while waiting" || true
    wait_loops=0
    wait_start="$(date +%s)"
    while flag_check "pre_menu_unpacking"; do
        wait_loops=$((wait_loops + 1))
        if [ $((wait_loops % 25)) -eq 0 ]; then
            "$SYSTEM_EMIT" process firstboot "WAITING_PREMENU_LOCK" "firstboot.sh/wait_pre_menu" "loops=$wait_loops" || true
        fi
        now="$(date +%s)"
        if [ $((now - wait_start)) -ge "$UNPACK_WAIT_TIMEOUT_SEC" ]; then
            log_message "Unpacker: firstboot pre_menu wait timed out; marking resumable failure state."
            FIRSTBOOT_FINAL_STATE="FAILED_TIMEOUT"
            FIRSTBOOT_FINAL_REASON="pre_menu_unpacking-timeout"
            write_unpack_state_failed_resumable
            break
        fi
        sleep 0.2
    done
    "$SYSTEM_EMIT" process firstboot "PREMENU_LOCK_CLEARED" "firstboot.sh/wait_pre_menu" "loops=$wait_loops" || true
fi

# Do not finalize firstboot while unpack coordinator still reports running.
unpack_wait_start="$(date +%s)"
while true; do
    unpack_state="$(read_unpack_state)"
    if [ "$unpack_state" != "running" ] && ! flag_check "pre_cmd_unpacking"; then
        break
    fi

    now="$(date +%s)"
    if [ $((now - unpack_wait_start)) -ge "$UNPACK_WAIT_TIMEOUT_SEC" ]; then
        log_message "Unpacker: firstboot completion gate timed out; marking resumable failure state."
        FIRSTBOOT_FINAL_STATE="FAILED_TIMEOUT"
        FIRSTBOOT_FINAL_REASON="completion-gate-timeout"
        write_unpack_state_failed_resumable
        break
    fi
    sleep 0.2
done

# create splore launcher if it doesn't already exist
if [ ! -f "$SPLORE_CART" ]; then
	touch "$SPLORE_CART" && log_message "firstboot.sh: created $SPLORE_CART"
else
	log_message "firstboot.sh: $SPLORE_CART already found."
fi

"$(get_python_path)" -O -m compileall /mnt/SDCARD/App/PyUI/main-ui/

show_firstboot_screen "$HAPPY_ICON" "Happy gaming.........." 5

flag_remove "unpacker_ui_visible"
flag_remove "$FIRSTBOOT_SCREEN_HOLD_FLAG"
log_message "Finished firstboot script"
"$SYSTEM_EMIT" process firstboot "COMPLETED" "firstboot.sh/shutdown" "platform=$PLATFORM" || true
