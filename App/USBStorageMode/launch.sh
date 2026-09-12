#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh
. /mnt/SDCARD/App/USBStorageMode/usb_gadget.sh

SAVE_POWEROFF=/mnt/SDCARD/spruce/scripts/save_poweroff.sh

if ! usb_gadget_platform_setup; then
    # This will run if PyUI isn't ready yet, providing a basic message.
    /mnt/SDCARD/App/PyUI/main-ui/devices/utils/display_text "USB Storage Mode is not supported on this device." &
    sleep 3
    exit 1
fi

# One shutdown path (SPR-HIGH-053). save_poweroff.sh --usb-storage stages
# stage 2 into /tmp, runs the device preparation, releases the gadget
# through usb_gadget_release, and reboots from /tmp - so nothing depends on
# the card after the LUN closes, which on TrimUI stock is the moment the
# card disappears (mdev's sdcard_remove). The realtime message listener is
# stopped here because it executes the MainUI bind on the card.
exit_usb_storage_mode() {
    log_message "USB Storage Mode: exiting ($1), handing over to save_poweroff.sh --usb-storage"
    log_and_display_message "Device will now reboot."
    sleep 3
    stop_pyui_message_writer
    sync
    if [ -x "$SAVE_POWEROFF" ]; then
        exec "$SAVE_POWEROFF" --reboot --usb-storage
    fi
    log_message "USB Storage Mode: $SAVE_POWEROFF missing, releasing the gadget and rebooting directly"
    usb_gadget_release
    device_run_reboot_cmd
}

# --- Main Execution ---

start_pyui_message_writer "1" # Wait for listener

# Warm up the display driver, mimicking other known-good apps
log_and_display_message "Loading..."
sleep 0.5

# 1. Wait for USB cable connection, using the reliable charging status check
while [ "$(device_get_charging_status)" = "Discharging" ]; do
    log_and_display_message "Please connect the USB cable to your computer. Press A to check again, or B to cancel."
    if confirm; then
        # Loop will re-check charging status
        :
    else
        # User pressed B
        log_and_display_message "Cancelled by user."
        sleep 1
        exit 0
    fi
done

# 2. Confirm entry into USB mode
log_and_display_message "Enter USB Mass Storage Mode?\nPress A to confirm, or B to cancel."
if confirm; then
    # User pressed A, continue
    :
else
    # User pressed B
    log_and_display_message "Cancelled by user."
    sleep 1
    exit 0
fi

# 3. Double-check connection and start
if [ "$(device_get_charging_status)" = "Discharging" ]; then
    log_and_display_message "USB Cable Disconnected."
    sleep 2
    exit 0
fi

# Disable idle/shutdown timer while in USB mode (device reboots on exit, so no need to restart)
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

# 4. Export. The PC must not be handed a filesystem the kernel still has
# mounted (SPR-MED-198), so wherever spruce owns the card the export is a
# card-less session: stage what it needs into /tmp and hand over to the
# shutdown, which unmounts cleanly, exports, waits, and reboots. Only where
# the system owns the card (device_system_handles_sdcard_unmount) is the
# mounted export kept.
if ! device_system_handles_sdcard_unmount; then
    if usb_session_stage; then
        log_and_display_message "Preparing the SD card for USB..."
        sleep 1
        stop_pyui_message_writer
        sync
        exec "$SAVE_POWEROFF" --usb-storage-export
    fi
    log_message "USB Storage Mode: session staging failed, falling back to the mounted export"
fi

log_and_display_message "Connecting USB Mass Storage Mode..."
configure_usb_gadget
log_and_display_message "" # Clear the "Connecting" message

# 4b. Legacy loop (mounted export)
while true; do
    if [ "$(device_get_charging_status)" = "Discharging" ]; then
        log_and_display_message "USB Cable Disconnected."
        exit_usb_storage_mode "cable disconnected"
    fi

    log_and_display_message "USB Mode Active.\nPress A to exit and reboot your device."
    if confirm; then
        exit_usb_storage_mode "A pressed"
    fi
    # Add a small sleep to prevent the loop from overwhelming the CPU
    sleep 1
done

exit 0

