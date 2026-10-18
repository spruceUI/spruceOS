#!/bin/sh

# BaseOS-my355 layer for the Miyoo Flip: sourced at the end of Flip.sh when Flip.cfg
# found BaseOS (baseos/my355.cfg), so these replace the stock definitions. PLATFORM=Flip.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/baseos_session_shield.sh"

# BaseOS replaces the Miyoo firmware: compare against its own releases.
check_if_fw_needs_update() {
    baseos_fw_needs_update
}

# No vendor flasher: BaseOS updates itself from a .bosupd at the card root.
perform_fw_update_Flip() {
    return 0
}

# No vendor UI to hand off to; init respawns BaseOS's own session instead.
device_stock_ui_command() {
    return 0
}

# BaseOS harvests only miyoo_inputd from the vendor services.
flip_start_vendor_services() {
    /usr/miyoo/bin/miyoo_inputd &
}

# Called under the /usr overlay and over it: stage 2 drops the overlay before it
# unmounts the card, and BaseOS's respawned session would remount it.
flip_shield_session() {
    shield_baseos_session /sbin/frontend-session
}
