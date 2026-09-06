#!/bin/sh

# USB Storage Mode gadget layer. Sourced by launch.sh (configure the gadget)
# and by save_poweroff.sh --usb-storage (release it during the shutdown).
# Needs $PLATFORM from helperFunctions.sh. Nothing here is executed on load.
#
# Why the release lives in the shutdown and not in the app (SPR-HIGH-053):
# on TrimUI stock, udev's block `watch` rule turns the mass-storage LUN
# closing /dev/mmcblk1p1 into a synthesized `change` uevent, which
# /sbin/mdev answers with /etc/mdev/sdcard_remove - the card is lazily
# unmounted, its mount point and /mnt/SDCARD are deleted. Anything the exit
# still needs from the card must therefore be in place BEFORE
# usb_gadget_release runs; save_poweroff.sh stages stage 2 into /tmp first.

# Platform table. Returns 1 on a platform without USB Storage Mode support.
usb_gadget_platform_setup() {
    case "$PLATFORM" in
        "A30")
            STORAGE_DEVICE="/dev/mmcblk0p1"
            MOUNT_POINT="/mnt/SDCARD"
            USB_GADGET_PATH="/sys/devices/platform/sunxi_usb_udc/gadget"
            LUN_PATH="$USB_GADGET_PATH/lun0"
            LUN_FILE="$LUN_PATH/file"
            ;;
        "Brick" | "SmartPro" | "BrickPro")
            STORAGE_DEVICE="/dev/mmcblk1p1"
            MOUNT_POINT="/mnt/SDCARD"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
            ;;
        "Flip")
            STORAGE_DEVICE="/dev/mmcblk1p1"
            MOUNT_POINT="/mnt/SDCARD"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
            USB_UDC_CONTROLLER="fcc00000.dwc3"
            USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"
            ;;
        "Pixel2")
            STORAGE_DEVICE="/dev/mmcblk0p3"
            MOUNT_POINT="/mnt/SDCARD/"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/rockchip"
            USB_UDC_CONTROLLER="ff300000.usb"
            USB_CONFIG_PATH="$USB_GADGET_PATH/configs/b.1"
            ;;
        "SmartProS")
            STORAGE_DEVICE="/dev/mmcblk1p1"
            MOUNT_POINT="/mnt/sdcard/mmcblk1p1"
            USB_GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
            USB_UDC_CONTROLLER="4100000.udc-controller"
            USB_CONFIG_PATH="$USB_GADGET_PATH/configs/c.1"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

safe_unmount_all() {
    for mpoint in $(mount | grep "$STORAGE_DEVICE" | awk '{print $3}' | sort -r); do
        for i in 1 2 3 4 5; do
            ! mount | grep -q " $mpoint " && break
            sync
            umount "$mpoint" 2>/dev/null && break
            sleep 1
        done
        if mount | grep -q " $mpoint "; then
            umount -f "$mpoint" 2>/dev/null
        fi
    done
    if grep -q "$MOUNT_POINT" /proc/mounts; then
        umount -f "$MOUNT_POINT" 2>/dev/null
    fi
}

# Release the mass-storage gadget: hand the block device back, unbind the
# UDC, drop the configuration link. Gadget only - no mounting or unmounting
# (save_poweroff.sh and stage 2 own the card from here on).
usb_gadget_release() {
    sync
    echo 3 > /proc/sys/vm/drop_caches
    case "$PLATFORM" in
        "A30")
            echo "" > "$LUN_FILE" 2>/dev/null
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            ;;
        "Brick" | "SmartPro" | "BrickPro")
            echo "" > $USB_GADGET_PATH/UDC 2>/dev/null
            rm -f $USB_GADGET_PATH/configs/c.1/mass_storage.usb0
            [ -d "$USB_GADGET_PATH/configs/c.1" ] && rmdir "$USB_GADGET_PATH/configs/c.1" 2>/dev/null
            [ -d "$USB_GADGET_PATH/functions/mass_storage.usb0" ] && rmdir "$USB_GADGET_PATH/functions/mass_storage.usb0" 2>/dev/null
            [ -d "$USB_GADGET_PATH/strings/0x409" ] && rmdir "$USB_GADGET_PATH/strings/0x409" 2>/dev/null
            ;;
        "Flip" | "Pixel2")
            echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            sleep 1
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            echo "" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
            rm -f "$USB_CONFIG_PATH/mass_storage.0" 2>/dev/null
            ;;
        "SmartProS")
            echo "" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
            sleep 1
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            sleep 2
            rm -f "$USB_CONFIG_PATH/mass_storage.0" 2>/dev/null
            ;;
    esac
    sync
}

# Legacy path: export with the card still mounted. Only for platforms whose
# system owns the card (device_system_handles_sdcard_unmount), where the
# card-less session below cannot take it away. Everywhere else the PC would
# be handed a filesystem the kernel still has mounted read-write (SPR-MED-198).
configure_usb_gadget() {
    log_message "Configuring USB gadget for $PLATFORM..."
    safe_unmount_all
    sync
    echo 3 > /proc/sys/vm/drop_caches
    usb_export_gadget
}

# Write the LUN, build the configuration, bind the UDC. Pure gadget work: the
# caller decides what state the card is in.
usb_export_gadget() {

    case "$PLATFORM" in
        "A30")
            echo "" > "$LUN_FILE" 2>/dev/null
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 0 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            sleep 1
            [ -f "$LUN_PATH/ro" ] && echo 0 > "$LUN_PATH/ro" 2>/dev/null
            [ -f "$LUN_PATH/nofua" ] && echo 0 > "$LUN_PATH/nofua" 2>/dev/null
            [ -f "$LUN_PATH/removable" ] && echo 1 > "$LUN_PATH/removable" 2>/dev/null
            echo "$STORAGE_DEVICE" > "$LUN_FILE" 2>/dev/null
            sleep 1
            [ -f "/sys/class/udc/sunxi_usb_udc/soft_connect" ] && echo 1 > /sys/class/udc/sunxi_usb_udc/soft_connect 2>/dev/null
            ;;
        "Brick" | "SmartPro" | "BrickPro")
            mkdir -p $USB_GADGET_PATH/functions/mass_storage.usb0
            echo "0x1d6b" > $USB_GADGET_PATH/idVendor
            echo "0x0104" > $USB_GADGET_PATH/idProduct
            echo "$STORAGE_DEVICE" > $USB_GADGET_PATH/functions/mass_storage.usb0/lun.0/file
            echo 1 > $USB_GADGET_PATH/functions/mass_storage.usb0/lun.0/removable
            mkdir -p $USB_GADGET_PATH/configs/c.1
            ln -s $USB_GADGET_PATH/functions/mass_storage.usb0 $USB_GADGET_PATH/configs/c.1/
            mkdir -p $USB_GADGET_PATH/strings/0x409
            echo "TrimUI" > $USB_GADGET_PATH/strings/0x409/manufacturer
            echo "TrimUI Device" > $USB_GADGET_PATH/strings/0x409/product
            echo "1234567890" > $USB_GADGET_PATH/strings/0x409/serialnumber
            echo "" > $USB_GADGET_PATH/UDC 2>/dev/null
            echo "musb-hdrc" > $USB_GADGET_PATH/UDC
            ;;
        "Flip")
            mkdir -p "$USB_GADGET_PATH/functions/mass_storage.0/lun.0" 2>/dev/null
            echo "1" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable" 2>/dev/null
            echo "0" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/ro" 2>/dev/null
            echo "$STORAGE_DEVICE" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file" 2>/dev/null
            [ -e "$USB_CONFIG_PATH/mass_storage.0" ] || ln -sf "$USB_GADGET_PATH/functions/mass_storage.0" "$USB_CONFIG_PATH/" 2>/dev/null
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            sleep 1
            echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            ;;
        "Pixel2")
            mkdir $USB_GADGET_PATH -m 0770
            echo "0x2207" > $USB_GADGET_PATH/idVendor
            echo "0x0000" > $USB_GADGET_PATH/idProduct
            echo "0x0200" > $USB_GADGET_PATH/bcdUSB
            mkdir $USB_GADGET_PATH/strings/0x409 -m 0770
            echo “0123456789ABCDEF” > $USB_GADGET_PATH/strings/0x409/serialnumber
            echo “GameKiddy” > $USB_GADGET_PATH/strings/0x409/manufacturer
            echo “Pixel2” > $USB_GADGET_PATH/strings/0x409/product
            mkdir $USB_CONFIG_PATH -m 0770
            mkdir $USB_CONFIG_PATH/strings/0x409 -m 0770
            echo "mass_storage" > $USB_CONFIG_PATH/strings/0x409/configuration
            mkdir $USB_GADGET_PATH/functions/mass_storage.0
            echo $STORAGE_DEVICE > $USB_GADGET_PATH/functions/mass_storage.0/lun.0/file
		    echo 1 > $USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable
		    echo 0 > $USB_GADGET_PATH/functions/mass_storage.0/lun.0/nofua
            ln -s $USB_GADGET_PATH/functions/mass_storage.0 $USB_GADGET_PATH/configs/b.1/mass_storage.0
            echo $USB_UDC_CONTROLLER > $USB_GADGET_PATH/UDC
            ;;
            "SmartProS")
            echo "" > "$USB_GADGET_PATH/UDC" 2>/dev/null
            mkdir -p "$USB_GADGET_PATH/functions/mass_storage.0"
            echo 1 > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/removable"
            echo 0 > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/ro"
            echo "$STORAGE_DEVICE" > "$USB_GADGET_PATH/functions/mass_storage.0/lun.0/file"
            mkdir -p "$USB_CONFIG_PATH/strings/0x409"
            echo "Mass Storage" > "$USB_CONFIG_PATH/strings/0x409/configuration"
            [ -L "$USB_CONFIG_PATH/mass_storage.0" ] || ln -s "$USB_GADGET_PATH/functions/mass_storage.0" "$USB_CONFIG_PATH/"
            sleep 1
            echo "$USB_UDC_CONTROLLER" > "$USB_GADGET_PATH/UDC"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Card-less USB session (SPR-MED-198)
#
# The PC must never be handed a filesystem the kernel still has mounted. So
# USB Storage Mode is run as a shutdown that pauses before the power command:
# the app stages this file plus a display tool, an input reader, a font and a
# background into USB_SESSION_DIR, hands over to save_poweroff.sh
# --usb-storage-export, stage 2 does its strict clean unmount, and then
# sources this file from /tmp and calls usb_session_run - export, static
# screen, wait for A or the cable, release, back to stage 2 for the reboot.
# Everything the session touches lives on the rootfs or in /tmp.
# ---------------------------------------------------------------------------
USB_SESSION_DIR="${USB_SESSION_DIR:-/tmp/usbstorage}"

# Rootfs-only library path: the platform cfg's LD_LIBRARY_PATH without the
# card entries (the same table repairSD.sh hand-codes per platform).
usb_session_rootfs_ld_path() {
    _out=""
    _old_ifs="$IFS"; IFS=:
    for _d in $LD_LIBRARY_PATH; do
        case "$_d" in ""|/mnt/SDCARD*|/mnt/sdcard*) continue ;; esac
        _out="${_out:+$_out:}$_d"
    done
    IFS="$_old_ifs"
    echo "${_out:-/usr/lib:/lib}"
}

# Copy what the session needs into USB_SESSION_DIR and record the platform
# facts it cannot source once the card is gone. Returns 1 if anything is
# missing, in which case the caller keeps the mounted export.
usb_session_stage() {
    _bin=/mnt/SDCARD/spruce/bin64
    [ "$PLATFORM_ARCHITECTURE" = "armhf" ] && _bin=/mnt/SDCARD/spruce/bin
    _font=/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf
    _bg=/mnt/SDCARD/spruce/imgs/bg_tree.png
    [ "${DISPLAY_WIDTH:-0}" -ge 1280 ] && _bg=/mnt/SDCARD/spruce/imgs/bg_tree_wide.png
    rm -rf "$USB_SESSION_DIR"
    mkdir -p "$USB_SESSION_DIR" || return 1
    # fsck.fat is optional: without it a dirty card is exported as it is.
    [ -f "$_bin/fsck.fat" ] && cp "$_bin/fsck.fat" "$USB_SESSION_DIR/fsck.fat" && chmod +x "$USB_SESSION_DIR/fsck.fat"
    for _f in "$_bin/display_text.elf" "$_bin/getevent" "$_font" "$_bg" /mnt/SDCARD/App/USBStorageMode/usb_gadget.sh; do
        if [ ! -f "$_f" ]; then
            log_message "USB Storage Mode: cannot stage the session, missing $_f"
            return 1
        fi
    done
    cp "$_bin/display_text.elf" "$USB_SESSION_DIR/display_text.elf" &&
    cp "$_bin/getevent" "$USB_SESSION_DIR/getevent" &&
    cp "$_font" "$USB_SESSION_DIR/font.ttf" &&
    cp "$_bg" "$USB_SESSION_DIR/bg.png" &&
    cp /mnt/SDCARD/App/USBStorageMode/usb_gadget.sh "$USB_SESSION_DIR/usb_gadget.sh" || return 1
    chmod +x "$USB_SESSION_DIR/display_text.elf" "$USB_SESSION_DIR/getevent"
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
        echo "USB_SESSION_LD_LIBRARY_PATH='$(usb_session_rootfs_ld_path)'"
    } > "$USB_SESSION_DIR/env" || return 1
    sync
    log_message "USB Storage Mode: session staged in $USB_SESSION_DIR"
    return 0
}

usb_session_log() {
    echo "usb session [$(cut -d' ' -f1 /proc/uptime 2>/dev/null)s]: $1"
}

usb_session_display() {
    usb_session_display_kill
    _text_width=$((DISPLAY_WIDTH - 80))
    LD_LIBRARY_PATH="$USB_SESSION_LD_LIBRARY_PATH" "$USB_SESSION_DIR/display_text.elf" \
        "$DISPLAY_WIDTH" "$DISPLAY_HEIGHT" "$DISPLAY_ROTATION" "$USB_SESSION_DIR/bg.png" "$1" \
        0 30 50 middle "$_text_width" eb db b2 "$USB_SESSION_DIR/font.ttf" 7f 7f 7f 0 1.0 \
        >>"$USB_SESSION_DIR/display.out" 2>&1 &
    USB_SESSION_DISPLAY_PID=$!
    sleep 0.5
    if kill -0 "$USB_SESSION_DISPLAY_PID" 2>/dev/null; then
        usb_session_log "display up (pid $USB_SESSION_DISPLAY_PID): $1"
    else
        usb_session_log "display EXITED at once: $1 - $(tail -1 "$USB_SESSION_DIR/display.out" 2>/dev/null)"
    fi
}

usb_session_display_kill() {
    [ -n "$USB_SESSION_DISPLAY_PID" ] && kill "$USB_SESSION_DISPLAY_PID" 2>/dev/null
    USB_SESSION_DISPLAY_PID=""
}

# Block until the cable is pulled or A is pressed. Prints which.
usb_session_wait_for_exit() {
    rm -f "$USB_SESSION_DIR/ge_out"
    "$USB_SESSION_DIR/getevent" "$EVENT_PATH_READ_INPUTS_SPRUCE" > "$USB_SESSION_DIR/ge_out" 2>/dev/null &
    _ge_pid=$!
    _why=""
    while [ -z "$_why" ]; do
        if [ "$(cat "$BATTERY/status" 2>/dev/null)" = "Discharging" ]; then
            _why="cable disconnected"
        elif grep -q "key $B_A" "$USB_SESSION_DIR/ge_out" 2>/dev/null; then
            _why="A pressed"
        else
            sleep 0.2
        fi
    done
    kill "$_ge_pid" 2>/dev/null
    echo "$_why"
}

# The FAT "not properly unmounted" flag, read straight from the block device
# (boot sector state byte: offset 65 on FAT32, 37 on FAT12/16; bit 0 = dirty).
# It is what the kernel warns about at the next mount and what Windows
# offers to "scan and fix", so read it twice: after the device's own
# unmount (must be clean) and after the PC gives the card back (clean only
# if the PC ejected). Prints e.g. "clean (0x00)" / "dirty (0x01)".
usb_card_dirty_flag() {
    _type=$(dd if="$SD_DEV" bs=1 skip=82 count=5 2>/dev/null)
    if [ "$_type" = "FAT32" ]; then _off=65; else _off=37; fi
    _byte=$(dd if="$SD_DEV" bs=1 skip=$_off count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    [ -n "$_byte" ] || { echo "unreadable"; return; }
    if [ $((0x$_byte & 1)) -eq 0 ]; then echo "clean (0x$_byte)"; else echo "dirty (0x$_byte)"; fi
}

# Runs inside stage 2, after the strict unmount, from the /tmp copy.
usb_session_run() {
    [ -f "$USB_SESSION_DIR/env" ] || { echo "usb session: no env in $USB_SESSION_DIR"; return 1; }
    . "$USB_SESSION_DIR/env"
    usb_gadget_platform_setup || { echo "usb session: no gadget table for $PLATFORM"; return 1; }
    # The whole point: refuse to export a mounted card.
    if grep -q "^$SD_DEV " /proc/mounts; then
        echo "usb session: $SD_DEV is still mounted, refusing to export"
        return 1
    fi
    # The FAT dirty flag is sticky: once set, neither a clean unmount nor a
    # clean eject ever clears it (fat_set_state leaves a pre-dirty volume
    # alone, Windows likewise), so a card cut once is offered "scan and fix"
    # on every insert for the rest of its life (SPR-MED-199). This is the one
    # moment the card is cleanly unmounted and quiesced with nothing else
    # running, and the repair the kernel asks for takes seconds (7.5 s for
    # 30 k files on a 58 GB card): run it, and only then export.
    _flag="$(usb_card_dirty_flag)"
    usb_session_log "dirty flag after the device's unmount: $_flag"
    case "$_flag" in
        dirty*)
            if [ -x "$USB_SESSION_DIR/fsck.fat" ]; then
                usb_session_display "Checking the SD card before USB mode..."
                _t0=$(cut -d' ' -f1 /proc/uptime)
                "$USB_SESSION_DIR/fsck.fat" -a "$SD_DEV" > "$USB_SESSION_DIR/fsck.out" 2>&1
                _rc=$?
                echo "usb session: fsck.fat -a rc=$_rc in $(awk -v a="$_t0" -v b="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN{print b-a}') s, flag now: $(usb_card_dirty_flag)"
                tail -3 "$USB_SESSION_DIR/fsck.out" 2>/dev/null | sed 's/^/usb session: fsck: /'
            else
                echo "usb session: no fsck.fat staged, exporting the card dirty"
            fi
            ;;
    esac
    usb_session_log "exporting $SD_DEV (unmounted)"
    usb_export_gadget
    usb_session_display "USB Mode Active. Press A to exit and reboot your device."
    _why="$(usb_session_wait_for_exit)"
    usb_session_log "exit ($_why)"
    usb_session_display "Device will now reboot."
    usb_gadget_release
    sleep 1
    usb_session_log "dirty flag after the PC gave the card back: $(usb_card_dirty_flag)"
    usb_session_display_kill
    [ -s "$USB_SESSION_DIR/display.out" ] && sed 's/^/usb session: display: /' "$USB_SESSION_DIR/display.out" | tail -6
    return 0
}
